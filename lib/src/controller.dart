import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import 'exception.dart';
import 'launcher.dart';
import 'presentation.dart';
import 'result.dart';
import 'session.dart';
import 'session_status.dart';
import 'status.dart';
import 'verification.dart';

/// Coordinates opening the hosted Checkout and waiting for its completion.
///
/// Completion is detected by whichever signal arrives first:
///
/// * the verified universal/app link that brings the customer back, or
/// * the public session status reaching `completed`, polled through a
///   [NoriaCheckoutStatusReader].
///
/// A single controller can be reused across many [open] calls; a new call
/// cancels the previous pending wait with [NoriaCheckoutCancelledException].
/// Every collaborator is injectable so the controller can be exercised in
/// widget and unit tests without a device or network.
class NoriaCheckoutController {
  /// Creates a controller.
  ///
  /// [appLinkStream] (or [appLinks]) provides the universal/app links;
  /// [launcher] opens the browser; [statusReader] polls the public session
  /// state; [clock] supplies the current time. All default to the platform
  /// implementations. [pollInterval] spaces status reads and
  /// [maxConsecutivePollFailures] bounds transient failures before giving
  /// up. [maxWait] caps how long [open] waits and defaults to
  /// [defaultMaxWait].
  NoriaCheckoutController({
    Stream<Uri>? appLinkStream,
    AppLinks? appLinks,
    NoriaCheckoutLauncher? launcher,
    NoriaCheckoutStatusReader? statusReader,
    DateTime Function()? clock,
    this.pollInterval = const Duration(milliseconds: 1500),
    this.maxConsecutivePollFailures = 5,
    this.maxWait = defaultMaxWait,
  }) : assert(!pollInterval.isNegative, 'pollInterval must not be negative'),
       assert(
         maxConsecutivePollFailures > 0,
         'maxConsecutivePollFailures must be positive',
       ),
       assert(maxWait > Duration.zero, 'maxWait must be positive'),
       _appLinkStream = appLinkStream ?? (appLinks ?? AppLinks()).uriLinkStream,
       _launcher = launcher ?? NoriaCheckoutLauncher.platform(),
       _statusReader = statusReader ?? NoriaCheckoutStatusReader.http(),
       _clock = clock ?? DateTime.now;

  /// Default upper bound for how long [open] waits, regardless of how far in
  /// the future the session expires.
  static const Duration defaultMaxWait = Duration(hours: 24);

  /// Upper bound for how long [open] waits for completion.
  final Duration maxWait;

  /// Delay between two reads of the public session status.
  final Duration pollInterval;

  /// Number of consecutive transient status failures tolerated before [open]
  /// fails with [NoriaCheckoutErrorCode.pollingFailed].
  final int maxConsecutivePollFailures;

  final Stream<Uri> _appLinkStream;
  final NoriaCheckoutLauncher _launcher;
  final NoriaCheckoutStatusReader _statusReader;
  final DateTime Function() _clock;

  StreamSubscription<Uri>? _activeSubscription;
  Completer<NoriaCheckoutResult>? _activeCompletion;
  int _generation = 0;

  /// Whether an [open] call is currently waiting for completion.
  bool get hasPending => _activeCompletion != null;

  /// Cancels the pending [open], if any, failing it with
  /// [NoriaCheckoutCancelledException].
  ///
  /// Called automatically by every new [open] and by [NoriaCheckoutButton]
  /// when it is disposed.
  void cancelPending() {
    _generation++;
    final StreamSubscription<Uri>? subscription = _activeSubscription;
    final Completer<NoriaCheckoutResult>? completion = _activeCompletion;
    _activeSubscription = null;
    _activeCompletion = null;
    // See the note in [open] about not awaiting cancel.
    unawaited(subscription?.cancel());
    if (completion != null && !completion.isCompleted) {
      completion.completeError(const NoriaCheckoutCancelledException());
    }
  }

  /// Verifies [session], opens the Checkout and waits for completion.
  ///
  /// [onOpened] fires as soon as the browser is presented, so the caller can
  /// release its busy state while the customer pays.
  ///
  /// On Android and iOS the future completes with a [NoriaCheckoutResult]
  /// when a verified return link arrives or the public status reaches
  /// `completed`. It fails with:
  ///
  /// * [NoriaCheckoutErrorCode.sessionNotCompleted] when the status becomes
  ///   `expired`, `cancelled` or `failed`;
  /// * [NoriaCheckoutErrorCode.returnTimeout] when the session expires first;
  /// * [NoriaCheckoutErrorCode.cancelled] when a newer call supersedes it;
  /// * [NoriaCheckoutErrorCode.pollingFailed], `sessionUnavailable` or
  ///   `invalidStatus` when the status endpoint cannot be trusted.
  ///
  /// On Flutter Web the future completes with `null` right after the Checkout
  /// tab is opened: the return page must validate the link with
  /// [isVerifiedCheckoutReturn] and confirm the payment with the backend.
  ///
  /// A `completed` status is a strong signal for the UX, but the canonical
  /// confirmation must still come from a signed webhook or a server-to-server
  /// query.
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
      onOpened?.call();
      return null;
    }

    cancelPending();
    final int generation = _generation;
    final Completer<NoriaCheckoutResult> completed =
        Completer<NoriaCheckoutResult>();
    final StreamSubscription<Uri> subscription = _appLinkStream.listen(
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
    _activeSubscription = subscription;
    _activeCompletion = completed;
    try {
      await _launch(checkoutUri, presentation);
      onOpened?.call();
      unawaited(
        _pollStatus(
          session: session,
          expectedCheckoutOrigin: expectedCheckoutOrigin,
          completion: completed,
          generation: generation,
        ),
      );
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
      if (identical(_activeSubscription, subscription)) {
        _activeSubscription = null;
        _activeCompletion = null;
        _generation++;
      }
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

  Future<void> _pollStatus({
    required NoriaCheckoutSession session,
    required Uri expectedCheckoutOrigin,
    required Completer<NoriaCheckoutResult> completion,
    required int generation,
  }) async {
    final Uri statusUrl = checkoutStatusUri(
      session,
      expectedCheckoutOrigin: expectedCheckoutOrigin,
    );
    bool stale() => completion.isCompleted || generation != _generation;
    void fail(Object error) {
      if (!stale()) {
        completion.completeError(error);
      }
    }

    int failures = 0;
    while (!stale()) {
      NoriaCheckoutSessionStatus? status;
      try {
        status = await _statusReader.read(statusUrl, session.clientSecret);
      } on NoriaCheckoutException catch (error) {
        fail(error);
        return;
      } on Object {
        status = null;
      }
      if (stale()) {
        return;
      }
      if (status == null) {
        failures++;
        if (failures >= maxConsecutivePollFailures) {
          fail(
            const NoriaCheckoutException(
              NoriaCheckoutErrorCode.pollingFailed,
              'Não foi possível acompanhar a confirmação do pagamento.',
            ),
          );
          return;
        }
      } else {
        failures = 0;
        if (status == NoriaCheckoutSessionStatus.completed) {
          completion.complete(
            NoriaCheckoutResult(
              sessionId: session.sessionId,
              returnUri: statusUrl,
            ),
          );
          return;
        }
        if (status.isTerminal) {
          fail(NoriaCheckoutStatusException(status));
          return;
        }
      }
      if (_clock().toUtc().isAfter(session.expiresAt)) {
        fail(
          const NoriaCheckoutException(
            NoriaCheckoutErrorCode.returnTimeout,
            'A sessão expirou antes da confirmação.',
          ),
        );
        return;
      }
      await Future<void>.delayed(pollInterval);
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
