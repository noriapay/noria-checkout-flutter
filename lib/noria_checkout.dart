library;

import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

typedef NoriaCreateSession = Future<NoriaCheckoutSession> Function();
typedef NoriaCheckoutCallback = void Function(NoriaCheckoutResult result);
typedef NoriaCheckoutLauncher = Future<bool> Function(
  Uri uri, {
  required LaunchMode mode,
  String? webOnlyWindowName,
});
typedef NoriaCheckoutStatusReader = Future<String?> Function(
  Uri statusUrl,
  String clientSecret,
);
typedef NoriaCheckoutCloser = Future<void> Function();

@immutable
class NoriaCheckoutSession {
  const NoriaCheckoutSession({
    required this.sessionId,
    required this.checkoutUrl,
    required this.clientSecret,
    required this.expiresAt,
    required this.returnState,
  });

  factory NoriaCheckoutSession.fromJson(Map<String, Object?> json) {
    return NoriaCheckoutSession(
      sessionId: (json['sessionId'] ?? json['id']) as String,
      checkoutUrl: json['checkoutUrl'] as String,
      clientSecret: json['clientSecret'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      returnState: json['returnState'] as String,
    );
  }

  final String sessionId;
  final String checkoutUrl;
  final String clientSecret;
  final DateTime expiresAt;
  final String returnState;

  @override
  String toString() =>
      'NoriaCheckoutSession(sessionId: $sessionId, expiresAt: $expiresAt, clientSecret: [REDACTED])';
}

@immutable
class NoriaCheckoutResult {
  const NoriaCheckoutResult({required this.sessionId});
  final String sessionId;
}

class NoriaCheckoutException implements Exception {
  const NoriaCheckoutException(this.message);
  final String message;

  @override
  String toString() => 'NoriaCheckoutException: $message';
}

class NoriaCheckoutCancelledException extends NoriaCheckoutException {
  const NoriaCheckoutCancelledException()
      : super('A espera pelo retorno anterior foi cancelada.');
}

enum NoriaCheckoutPresentation { inAppBrowser, redirect }

final RegExp _sessionId = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

bool _isSecure(Uri value) {
  return value.scheme == 'https' ||
      (value.scheme == 'http' &&
          (value.host == 'localhost' || value.host == '127.0.0.1'));
}

Uri verifiedCheckoutUri(
  NoriaCheckoutSession session, {
  required Uri expectedCheckoutOrigin,
  DateTime? now,
}) {
  if (!_sessionId.hasMatch(session.sessionId)) {
    throw const NoriaCheckoutException('sessionId inválido.');
  }
  if (session.clientSecret.length < 20 || session.clientSecret.length > 256) {
    throw const NoriaCheckoutException('clientSecret inválido.');
  }
  if (session.returnState.length < 16 || session.returnState.length > 256) {
    throw const NoriaCheckoutException('returnState inválido.');
  }
  if (!session.expiresAt.isAfter((now ?? DateTime.now()).toUtc())) {
    throw const NoriaCheckoutException('A sessão expirou.');
  }
  final Uri uri = Uri.parse(session.checkoutUrl);
  final bool validExpectedOrigin = _isSecure(expectedCheckoutOrigin) &&
      expectedCheckoutOrigin.userInfo.isEmpty &&
      (expectedCheckoutOrigin.path.isEmpty ||
          expectedCheckoutOrigin.path == '/') &&
      expectedCheckoutOrigin.query.isEmpty &&
      expectedCheckoutOrigin.fragment.isEmpty;
  final bool sameOrigin = uri.scheme == expectedCheckoutOrigin.scheme &&
      uri.host == expectedCheckoutOrigin.host &&
      uri.port == expectedCheckoutOrigin.port;
  if (!_isSecure(uri) || uri.userInfo.isNotEmpty || !validExpectedOrigin) {
    throw const NoriaCheckoutException('checkoutUrl insegura.');
  }
  if (!sameOrigin) {
    throw const NoriaCheckoutException('Origem do Checkout não autorizada.');
  }
  if (uri.path != '/session/${session.sessionId}') {
    throw const NoriaCheckoutException('checkoutUrl não corresponde à sessão.');
  }
  if (uri.queryParameters.containsKey('client_secret') ||
      uri.queryParameters.containsKey('clientSecret')) {
    throw const NoriaCheckoutException(
      'clientSecret não pode estar na query string.',
    );
  }
  if (uri.hasQuery || uri.hasFragment) {
    throw const NoriaCheckoutException(
      'checkoutUrl não pode conter query ou fragmento.',
    );
  }
  return uri.replace(fragment: 'client_secret=${session.clientSecret}');
}

bool isVerifiedCheckoutReturn(
  Uri value, {
  required Uri expectedReturnUrl,
  required NoriaCheckoutSession session,
}) {
  final bool sameEndpoint = value.scheme == expectedReturnUrl.scheme &&
      value.host == expectedReturnUrl.host &&
      value.port == expectedReturnUrl.port &&
      value.path == expectedReturnUrl.path;
  final Map<String, List<String>> parameters = value.queryParametersAll;
  final bool exactParameters = parameters.length == 2 &&
      parameters['noria_checkout_session']?.length == 1 &&
      parameters['state']?.length == 1;
  return _isSecure(expectedReturnUrl) &&
      expectedReturnUrl.userInfo.isEmpty &&
      expectedReturnUrl.query.isEmpty &&
      expectedReturnUrl.fragment.isEmpty &&
      value.userInfo.isEmpty &&
      value.fragment.isEmpty &&
      sameEndpoint &&
      exactParameters &&
      value.queryParameters['noria_checkout_session'] == session.sessionId &&
      value.queryParameters['state'] == session.returnState;
}

class NoriaCheckoutController {
  NoriaCheckoutController({
    AppLinks? appLinks,
    Stream<Uri>? appLinkStream,
    NoriaCheckoutLauncher? launcher,
    NoriaCheckoutStatusReader? statusReader,
    NoriaCheckoutCloser? closer,
    this.pollInterval = const Duration(milliseconds: 1500),
    this.maxConsecutivePollFailures = 5,
  })  : assert(!pollInterval.isNegative),
        assert(maxConsecutivePollFailures > 0),
        _appLinkStream =
            appLinkStream ?? (appLinks ?? AppLinks()).uriLinkStream,
        _launcher = launcher ?? launchUrl,
        _statusReader = statusReader ?? _readCheckoutStatus,
        _closer = closer ?? _closeCheckoutBrowser;

  final Stream<Uri> _appLinkStream;
  final NoriaCheckoutLauncher _launcher;
  final NoriaCheckoutStatusReader _statusReader;
  final NoriaCheckoutCloser _closer;
  final Duration pollInterval;
  final int maxConsecutivePollFailures;
  StreamSubscription<Uri>? _activeSubscription;
  Completer<NoriaCheckoutResult>? _activeCompletion;
  int _generation = 0;

  static Future<String?> _readCheckoutStatus(
    Uri statusUrl,
    String clientSecret,
  ) async {
    final http.Response response = await http.get(
      statusUrl,
      headers: <String, String>{
        'X-Checkout-Secret': clientSecret,
        'Cache-Control': 'no-store',
      },
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode == 401 || response.statusCode == 404) {
      throw const NoriaCheckoutException(
        'A sessão de pagamento não está disponível.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?> || decoded['status'] is! String) {
      throw const NoriaCheckoutException(
        'O Checkout retornou um estado inválido.',
      );
    }
    final String status = decoded['status'] as String;
    if (!const <String>{
      'open',
      'processing',
      'completed',
      'expired',
      'cancelled',
      'failed',
    }.contains(status)) {
      throw const NoriaCheckoutException(
        'O Checkout retornou um estado inválido.',
      );
    }
    return status;
  }

  static Future<void> _closeCheckoutBrowser() async {
    if (await supportsCloseForLaunchMode(LaunchMode.inAppBrowserView)) {
      await closeInAppWebView();
    }
  }

  static Uri _statusUrlFor(
    NoriaCheckoutSession session,
    Uri expectedCheckoutOrigin,
  ) {
    return expectedCheckoutOrigin.replace(
      path: '/v1/public/checkout-session/${session.sessionId}',
      query: null,
      fragment: null,
    );
  }

  static NoriaCheckoutException _terminalStatusError(String status) {
    return NoriaCheckoutException(
      'O pagamento terminou com o estado $status.',
    );
  }

  Future<void> cancelPending() async {
    _generation++;
    final StreamSubscription<Uri>? subscription = _activeSubscription;
    final Completer<NoriaCheckoutResult>? completion = _activeCompletion;
    _activeSubscription = null;
    _activeCompletion = null;
    await subscription?.cancel();
    if (completion != null && !completion.isCompleted) {
      completion.completeError(const NoriaCheckoutCancelledException());
    }
  }

  Future<void> _pollStatus({
    required NoriaCheckoutSession session,
    required Uri expectedCheckoutOrigin,
    required Completer<NoriaCheckoutResult> completion,
    required int generation,
  }) async {
    final Uri statusUrl = _statusUrlFor(session, expectedCheckoutOrigin);
    int failures = 0;
    while (!completion.isCompleted && generation == _generation) {
      try {
        final String? status = await _statusReader(
          statusUrl,
          session.clientSecret,
        );
        if (generation != _generation || completion.isCompleted) return;
        if (status == null) {
          failures++;
        } else {
          failures = 0;
        }
        switch (status) {
          case 'completed':
            completion.complete(
              NoriaCheckoutResult(sessionId: session.sessionId),
            );
            return;
          case 'expired':
          case 'cancelled':
          case 'failed':
            completion.completeError(_terminalStatusError(status!));
            return;
        }
      } on NoriaCheckoutException catch (error) {
        if (!completion.isCompleted && generation == _generation) {
          completion.completeError(error);
        }
        return;
      } catch (_) {
        failures++;
      }
      if (failures >= maxConsecutivePollFailures) {
        if (!completion.isCompleted && generation == _generation) {
          completion.completeError(
            const NoriaCheckoutException(
              'Não foi possível acompanhar a confirmação do pagamento.',
            ),
          );
        }
        return;
      }
      if (DateTime.now().toUtc().isAfter(session.expiresAt)) {
        if (!completion.isCompleted && generation == _generation) {
          completion.completeError(
            const NoriaCheckoutException(
              'A sessão expirou antes da confirmação.',
            ),
          );
        }
        return;
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  Future<NoriaCheckoutResult?> open({
    required NoriaCheckoutSession session,
    required Uri expectedCheckoutOrigin,
    required Uri returnUrl,
    NoriaCheckoutPresentation presentation =
        NoriaCheckoutPresentation.inAppBrowser,
    VoidCallback? onOpened,
  }) async {
    final Uri checkoutUri = verifiedCheckoutUri(
      session,
      expectedCheckoutOrigin: expectedCheckoutOrigin,
    );
    if (!_isSecure(returnUrl) || returnUrl.userInfo.isNotEmpty) {
      throw const NoriaCheckoutException('returnUrl insegura.');
    }
    if (kIsWeb) {
      final bool opened = await _launcher(
        checkoutUri,
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: presentation == NoriaCheckoutPresentation.redirect
            ? '_self'
            : '_blank',
      );
      if (!opened) {
        throw const NoriaCheckoutException(
          'Não foi possível abrir o Checkout.',
        );
      }
      onOpened?.call();
      return null;
    }

    await cancelPending();
    final int generation = _generation;
    final Completer<NoriaCheckoutResult> completed =
        Completer<NoriaCheckoutResult>();
    late final StreamSubscription<Uri> subscription;
    subscription = _appLinkStream.listen((Uri value) {
      if (!isVerifiedCheckoutReturn(
        value,
        expectedReturnUrl: returnUrl,
        session: session,
      )) {
        return;
      }
      if (!completed.isCompleted) {
        completed.complete(NoriaCheckoutResult(sessionId: session.sessionId));
      }
    });
    _activeCompletion = completed;
    _activeSubscription = subscription;
    try {
      final bool opened = await _launcher(
        checkoutUri,
        mode: presentation == NoriaCheckoutPresentation.redirect
            ? LaunchMode.externalApplication
            : LaunchMode.inAppBrowserView,
      );
      if (!opened) {
        throw const NoriaCheckoutException(
          'Não foi possível abrir o Checkout.',
        );
      }
      onOpened?.call();
      unawaited(
        _pollStatus(
          session: session,
          expectedCheckoutOrigin: expectedCheckoutOrigin,
          completion: completed,
          generation: generation,
        ),
      );
      final Duration untilExpiry = session.expiresAt.difference(
        DateTime.now().toUtc(),
      );
      final Duration remaining = untilExpiry < const Duration(seconds: 1)
          ? const Duration(seconds: 1)
          : untilExpiry > const Duration(hours: 24)
              ? const Duration(hours: 24)
              : untilExpiry;
      final NoriaCheckoutResult result = await completed.future.timeout(
        remaining,
        onTimeout: () => throw const NoriaCheckoutException(
          'A sessão expirou antes do retorno.',
        ),
      );
      if (presentation == NoriaCheckoutPresentation.inAppBrowser) {
        try {
          await _closer();
        } catch (_) {
          // A confirmação já é canônica. Fechar o navegador é apenas UX.
        }
      }
      return result;
    } finally {
      if (identical(_activeSubscription, subscription)) {
        _activeSubscription = null;
        _activeCompletion = null;
        _generation++;
      }
      await subscription.cancel();
    }
  }
}

class NoriaCheckoutButton extends StatefulWidget {
  const NoriaCheckoutButton({
    required this.createSession,
    required this.expectedCheckoutOrigin,
    required this.returnUrl,
    required this.child,
    this.onComplete,
    this.onError,
    this.controller,
    this.presentation = NoriaCheckoutPresentation.inAppBrowser,
    this.enabled = true,
    super.key,
  });

  final NoriaCreateSession createSession;
  final Uri expectedCheckoutOrigin;
  final Uri returnUrl;
  final Widget child;
  final NoriaCheckoutCallback? onComplete;
  final ValueChanged<Object>? onError;
  final NoriaCheckoutController? controller;
  final NoriaCheckoutPresentation presentation;
  final bool enabled;

  @override
  State<NoriaCheckoutButton> createState() => _NoriaCheckoutButtonState();
}

class NoriaCheckoutButtonLabel extends StatelessWidget {
  const NoriaCheckoutButtonLabel({
    this.prefix = 'Pagar com a ',
    super.key,
  });

  final String prefix;

  @override
  Widget build(BuildContext context) {
    final TextStyle inherited = DefaultTextStyle.of(context).style;
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(prefix, style: inherited),
          Image.asset(
            'assets/images/noria-wordmark.png',
            package: 'noria_checkout',
            height: 16,
            fit: BoxFit.contain,
            color: inherited.color,
            colorBlendMode: BlendMode.srcIn,
          ),
        ],
      ),
    );
  }
}

class _NoriaCheckoutButtonState extends State<NoriaCheckoutButton> {
  bool _busy = false;
  int _attempt = 0;

  NoriaCheckoutController get _controller =>
      widget.controller ?? (_ownedController ??= NoriaCheckoutController());

  NoriaCheckoutController? _ownedController;

  Future<void> _open() async {
    if (_busy || !widget.enabled) return;
    final int attempt = ++_attempt;
    setState(() => _busy = true);
    try {
      final NoriaCheckoutSession session = await widget.createSession();
      final NoriaCheckoutResult? result = await _controller.open(
        session: session,
        expectedCheckoutOrigin: widget.expectedCheckoutOrigin,
        returnUrl: widget.returnUrl,
        presentation: widget.presentation,
        onOpened: () {
          if (mounted && attempt == _attempt) {
            setState(() => _busy = false);
          }
        },
      );
      if (result != null) widget.onComplete?.call(result);
    } catch (error) {
      if (error is! NoriaCheckoutCancelledException) {
        widget.onError?.call(error);
      }
    } finally {
      if (mounted && attempt == _attempt && _busy) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    _attempt++;
    _ownedController?.cancelPending();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: widget.enabled && !_busy,
      label: 'Abrir Noria Checkout',
      child: FilledButton(
        onPressed: widget.enabled && !_busy ? _open : null,
        child: _busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : widget.child,
      ),
    );
  }
}
