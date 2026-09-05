import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import 'exception.dart';
import 'launcher.dart';
import 'presentation.dart';
import 'result.dart';
import 'session.dart';
import 'verification.dart';

/// Coordinates opening the hosted Checkout and waiting for the verified
/// return link.
///
/// A single controller can be reused across many [open] calls. Every
/// collaborator is injectable so the controller can be exercised in widget and
/// unit tests without a device.
class NoriaCheckoutController {
  /// Creates a controller.
  ///
  /// [appLinks] provides the universal/app link stream; [launcher] opens the
  /// browser; [clock] supplies the current time for expiry checks. All default
  /// to the platform implementations. [maxWait] caps how long [open] waits
  /// for a return link and defaults to [defaultMaxWait].
  NoriaCheckoutController({
    AppLinks? appLinks,
    NoriaCheckoutLauncher? launcher,
    DateTime Function()? clock,
    this.maxWait = defaultMaxWait,
  }) : assert(maxWait > Duration.zero, 'maxWait must be positive'),
       _appLinks = appLinks ?? AppLinks(),
       _launcher = launcher ?? NoriaCheckoutLauncher.platform(),
       _clock = clock ?? DateTime.now;

  /// Default upper bound for how long [open] waits for a return link,
  /// regardless of how far in the future the session expires.
  static const Duration defaultMaxWait = Duration(hours: 24);

  /// Upper bound for how long [open] waits for a return link.
  final Duration maxWait;

  final AppLinks _appLinks;
  final NoriaCheckoutLauncher _launcher;
  final DateTime Function() _clock;

  /// Verifies [session], opens the Checkout and waits for the verified
  /// return link.
  ///
  /// On Android and iOS the future completes with a [NoriaCheckoutResult] once
  /// a link matching [returnUrl], the session id and the state arrives, or
  /// fails with [NoriaCheckoutErrorCode.returnTimeout] when the session
  /// expires first. Links that do not verify are ignored silently.
  ///
  /// On Flutter Web the future completes with `null` right after the Checkout
  /// tab is opened: the return page must validate the link with
  /// [isVerifiedCheckoutReturn] and confirm the payment with the backend.
  ///
  /// Throws [NoriaCheckoutException] for every validation or platform failure.
  Future<NoriaCheckoutResult?> open({
    required NoriaCheckoutSession session,
    required Uri expectedCheckoutOrigin,
    required Uri returnUrl,
    NoriaCheckoutPresentation presentation =
        NoriaCheckoutPresentation.inAppBrowser,
  }) async {
    final Uri checkoutUri = verifiedCheckoutUri(
      session,
      expectedCheckoutOrigin: expectedCheckoutOrigin,
      now: _clock(),
    );
    if (!isSecureCheckoutUri(returnUrl) ||
        returnUrl.userInfo.isNotEmpty ||
        returnUrl.hasQuery ||
        returnUrl.hasFragment) {
      throw const NoriaCheckoutException(
        NoriaCheckoutErrorCode.insecureUrl,
        'returnUrl deve ser https e não pode conter user info, query ou '
        'fragmento.',
      );
    }

    if (kIsWeb) {
      await _launch(checkoutUri, presentation);
      return null;
    }

    final Completer<NoriaCheckoutResult> completed =
        Completer<NoriaCheckoutResult>();
    final StreamSubscription<Uri> subscription = _appLinks.uriLinkStream.listen(
      (Uri link) {
        if (completed.isCompleted) {
          return;
        }
        if (isVerifiedCheckoutReturn(
          link,
          expectedReturnUrl: returnUrl,
          session: session,
        )) {
          completed.complete(
            NoriaCheckoutResult(sessionId: session.sessionId, returnUri: link),
          );
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        // A broken link stream must not hang the caller forever.
        if (!completed.isCompleted) {
          completed.completeError(
            NoriaCheckoutException(
              NoriaCheckoutErrorCode.launchFailed,
              'Falha ao observar o link de retorno.',
              cause: error,
            ),
            stackTrace,
          );
        }
      },
    );
    try {
      await _launch(checkoutUri, presentation);
      final NoriaCheckoutResult result = await completed.future.timeout(
        _remainingLifetime(session),
        onTimeout: () => throw const NoriaCheckoutException(
          NoriaCheckoutErrorCode.returnTimeout,
          'A sessão expirou antes do retorno.',
        ),
      );
      if (presentation == NoriaCheckoutPresentation.inAppBrowser) {
        await _launcher.closeInAppBrowser();
      }
      return result;
    } finally {
      // Not awaited on purpose: a broadcast subscription's cancel future is
      // bound to the root zone, and awaiting it would stall callers running
      // under FakeAsync (every Flutter widget test) without any benefit here.
      unawaited(subscription.cancel());
    }
  }

  Future<void> _launch(Uri uri, NoriaCheckoutPresentation presentation) async {
    final bool opened;
    try {
      opened = await _launcher.launch(uri, presentation);
    } on NoriaCheckoutException {
      rethrow;
    } on Object catch (error) {
      throw NoriaCheckoutException(
        NoriaCheckoutErrorCode.launchFailed,
        'Não foi possível abrir o Checkout.',
        cause: error,
      );
    }
    if (!opened) {
      throw const NoriaCheckoutException(
        NoriaCheckoutErrorCode.launchFailed,
        'Não foi possível abrir o Checkout.',
      );
    }
  }

  Duration _remainingLifetime(NoriaCheckoutSession session) {
    final Duration untilExpiry = session.expiresAt.difference(_clock().toUtc());
    final Duration floored = untilExpiry < _minWait ? _minWait : untilExpiry;
    return floored > maxWait ? maxWait : floored;
  }

  /// Lower bound so a session that expires "right now" still gets a chance
  /// to deliver a return link that is already in flight.
  static const Duration _minWait = Duration(seconds: 1);
}
