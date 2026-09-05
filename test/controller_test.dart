import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noria_checkout/noria_checkout.dart';

import 'support/fixtures.dart';

class _RecordingLauncher extends FakeLauncher {
  _RecordingLauncher(this.events);

  final List<String> events;

  @override
  Future<bool> launch(Uri url, NoriaCheckoutPresentation presentation) {
    events.add('launch');
    return super.launch(url, presentation);
  }
}

class _RecordingStatusReader extends FakeStatusReader {
  _RecordingStatusReader(this.events)
    : super(<Object?>[NoriaCheckoutSessionStatus.completed]);

  final List<String> events;

  @override
  Future<NoriaCheckoutSessionStatus?> read(Uri statusUrl, String clientSecret) {
    events.add('status');
    return super.read(statusUrl, clientSecret);
  }
}

void main() {
  late FakeAppLinks appLinks;
  late FakeLauncher launcher;
  late FakeStatusReader statusReader;
  late NoriaCheckoutController controller;

  NoriaCheckoutController build({
    Duration pollInterval = Duration.zero,
    int maxConsecutivePollFailures = 5,
    Duration maxWait = NoriaCheckoutController.defaultMaxWait,
  }) {
    return NoriaCheckoutController(
      appLinks: appLinks,
      launcher: launcher,
      statusReader: statusReader,
      clock: () => now,
      pollInterval: pollInterval,
      maxConsecutivePollFailures: maxConsecutivePollFailures,
      maxWait: maxWait,
    );
  }

  setUp(() {
    appLinks = FakeAppLinks();
    launcher = FakeLauncher();
    statusReader = FakeStatusReader();
    controller = build();
  });

  tearDown(() => appLinks.dispose());

  Future<NoriaCheckoutResult?> open({
    NoriaCheckoutSession? value,
    Uri? origin,
    Uri? back,
    NoriaCheckoutPresentation presentation =
        NoriaCheckoutPresentation.inAppBrowser,
    VoidCallback? onOpened,
  }) {
    return controller.open(
      session: value ?? session(),
      expectedCheckoutOrigin: origin ?? checkoutOrigin,
      returnUrl: back ?? returnUrl,
      presentation: presentation,
      onOpened: onOpened,
    );
  }

  test('opens the verified URI and completes on the genuine return', () async {
    bool opened = false;
    final Future<NoriaCheckoutResult?> pending = open(
      onOpened: () => opened = true,
    );
    await pumpEventQueue();
    expect(opened, isTrue);

    expect(launcher.launched, hasLength(1));
    expect(launcher.launched.single.fragment, startsWith('client_secret='));
    expect(
      launcher.presentations.single,
      NoriaCheckoutPresentation.inAppBrowser,
    );
    expect(appLinks.hasListener, isTrue);

    final Uri link = returnLinkFor(session());
    appLinks.emit(link);
    final NoriaCheckoutResult? result = await pending;

    expect(result, NoriaCheckoutResult(sessionId: sessionId, returnUri: link));
    expect(launcher.closeCalls, 1);
    expect(appLinks.hasListener, isFalse);
  });

  test('ignores links that do not verify and keeps waiting', () async {
    final Future<NoriaCheckoutResult?> pending = open();
    await pumpEventQueue();

    appLinks.emit(Uri.parse('https://shop.example/other'));
    appLinks.emit(
      Uri.parse(
        '$returnUrl?noria_checkout_session=$sessionId&state=forged-state-value',
      ),
    );
    await pumpEventQueue();
    expect(appLinks.hasListener, isTrue);

    appLinks.emit(returnLinkFor(session()));
    expect((await pending)?.sessionId, sessionId);
  });

  test('does not close the browser for the redirect presentation', () async {
    final Future<NoriaCheckoutResult?> pending = open(
      presentation: NoriaCheckoutPresentation.redirect,
    );
    await pumpEventQueue();
    expect(launcher.presentations.single, NoriaCheckoutPresentation.redirect);

    appLinks.emit(returnLinkFor(session()));
    await pending;
    expect(launcher.closeCalls, 0);
  });

  test('fails with launchFailed when the browser cannot be opened', () async {
    launcher.opened = false;
    bool opened = false;
    await expectLater(
      open(onOpened: () => opened = true),
      throwsCheckoutError(NoriaCheckoutErrorCode.launchFailed),
    );
    expect(opened, isFalse);
    expect(statusReader.reads, 0);
    expect(appLinks.hasListener, isFalse);
  });

  test('wraps platform exceptions thrown by the launcher', () async {
    launcher.error = StateError('no browser');
    await expectLater(
      open(),
      throwsA(
        isA<NoriaCheckoutException>()
            .having((e) => e.code, 'code', NoriaCheckoutErrorCode.launchFailed)
            .having((e) => e.cause, 'cause', isA<StateError>()),
      ),
    );
    expect(appLinks.hasListener, isFalse);
  });

  test('fails with launchFailed when the link stream errors', () async {
    final Future<NoriaCheckoutResult?> pending = open();
    await pumpEventQueue();
    appLinks.fail(StateError('stream broken'));
    await expectLater(
      pending,
      throwsCheckoutError(NoriaCheckoutErrorCode.launchFailed),
    );
    expect(appLinks.hasListener, isFalse);
  });

  test('validates the session before touching the browser', () async {
    await expectLater(
      open(value: session(expiresAt: now)),
      throwsCheckoutError(NoriaCheckoutErrorCode.sessionExpired),
    );
    expect(launcher.launched, isEmpty);
    expect(appLinks.hasListener, isFalse);
  });

  for (final String unsafe in <String>[
    'http://shop.example/payment/return',
    'https://shop.example/payment/return?x=1',
    'https://shop.example/payment/return#x',
    'https://u:p@shop.example/payment/return',
    'myapp://payment/return',
  ]) {
    test('rejects the return URL "$unsafe"', () async {
      await expectLater(
        open(back: Uri.parse(unsafe)),
        throwsCheckoutError(NoriaCheckoutErrorCode.insecureUrl),
      );
      expect(launcher.launched, isEmpty);
    });
  }

  test('times out when the session expires before the return', () async {
    // The controller floors the wait at one second, so a session that expires
    // immediately still exercises the real timer path.
    final NoriaCheckoutSession shortLived = session(
      expiresAt: now.add(const Duration(milliseconds: 10)),
    );
    final Stopwatch elapsed = Stopwatch()..start();
    await expectLater(
      open(value: shortLived),
      throwsCheckoutError(NoriaCheckoutErrorCode.returnTimeout),
    );
    expect(elapsed.elapsed, greaterThanOrEqualTo(const Duration(seconds: 1)));
    expect(appLinks.hasListener, isFalse);
    expect(launcher.closeCalls, 0);
  });

  test('never waits longer than maxWait', () async {
    controller = build(maxWait: const Duration(milliseconds: 100));
    final NoriaCheckoutSession longLived = session(
      expiresAt: now.add(const Duration(days: 30)),
    );
    final Stopwatch elapsed = Stopwatch()..start();
    await expectLater(
      open(value: longLived),
      throwsCheckoutError(NoriaCheckoutErrorCode.returnTimeout),
    );
    expect(elapsed.elapsed, lessThan(const Duration(seconds: 1)));
    expect(appLinks.hasListener, isFalse);
  });

  test('rejects a non-positive maxWait', () {
    expect(() => build(maxWait: Duration.zero), throwsAssertionError);
  });

  test('rejects invalid polling settings', () {
    expect(
      () => build(pollInterval: const Duration(seconds: -1)),
      throwsAssertionError,
    );
    expect(() => build(maxConsecutivePollFailures: 0), throwsAssertionError);
  });

  test('exposes the default maxWait', () {
    expect(controller.maxWait, NoriaCheckoutController.defaultMaxWait);
    expect(NoriaCheckoutController.defaultMaxWait, const Duration(hours: 24));
  });

  test('defaults match the documented polling policy', () {
    final NoriaCheckoutController defaults = NoriaCheckoutController(
      appLinks: appLinks,
      launcher: launcher,
      statusReader: statusReader,
    );
    expect(defaults.pollInterval, const Duration(milliseconds: 1500));
    expect(defaults.maxConsecutivePollFailures, 5);
    expect(defaults.hasPending, isFalse);
  });

  group('public session status', () {
    test('completes the UX when the status reaches completed', () async {
      statusReader = FakeStatusReader(<Object?>[
        NoriaCheckoutSessionStatus.open,
        NoriaCheckoutSessionStatus.processing,
        NoriaCheckoutSessionStatus.completed,
      ]);
      controller = build();
      bool opened = false;

      final NoriaCheckoutResult? result = await open(
        onOpened: () => opened = true,
      );

      final Uri statusUrl = Uri.parse(
        '${checkoutOrigin.origin}/v1/public/checkout-session/$sessionId',
      );
      expect(result?.sessionId, sessionId);
      expect(result?.returnUri, statusUrl);
      expect(statusReader.reads, 3);
      expect(statusReader.requestedUrls.toSet(), <Uri>{statusUrl});
      expect(statusUrl.query, isEmpty);
      expect(statusUrl.fragment, isEmpty);
      expect(statusReader.suppliedSecrets.toSet(), <String>{
        session().clientSecret,
      });
      expect(opened, isTrue);
      expect(launcher.closeCalls, 1);
      expect(appLinks.hasListener, isFalse);
      expect(controller.hasPending, isFalse);
    });

    test('opens the browser before reading the status', () async {
      final List<String> events = <String>[];
      launcher = _RecordingLauncher(events);
      statusReader = _RecordingStatusReader(events);
      controller = build();

      await open();

      expect(events, <String>['launch', 'status']);
    });

    for (final NoriaCheckoutSessionStatus terminal
        in <NoriaCheckoutSessionStatus>[
          NoriaCheckoutSessionStatus.expired,
          NoriaCheckoutSessionStatus.cancelled,
          NoriaCheckoutSessionStatus.failed,
        ]) {
      test('fails with sessionNotCompleted on ${terminal.name}', () async {
        statusReader = FakeStatusReader(<Object?>[terminal]);
        controller = build();

        await expectLater(
          open(),
          throwsA(
            isA<NoriaCheckoutStatusException>()
                .having((e) => e.status, 'status', terminal)
                .having(
                  (e) => e.code,
                  'code',
                  NoriaCheckoutErrorCode.sessionNotCompleted,
                ),
          ),
        );
        expect(launcher.closeCalls, 0);
        expect(appLinks.hasListener, isFalse);
      });
    }

    test('bounds consecutive transient failures', () async {
      statusReader = FakeStatusReader(<Object?>[
        null,
        StateError('synthetic network failure'),
        null,
      ]);
      controller = build(maxConsecutivePollFailures: 2);

      await expectLater(
        open(),
        throwsCheckoutError(NoriaCheckoutErrorCode.pollingFailed),
      );
      expect(statusReader.reads, 2);
    });

    test('resets the failure counter after a successful read', () async {
      statusReader = FakeStatusReader(<Object?>[
        null,
        NoriaCheckoutSessionStatus.open,
        null,
        NoriaCheckoutSessionStatus.completed,
      ]);
      controller = build(maxConsecutivePollFailures: 2);

      expect((await open())?.sessionId, sessionId);
      expect(statusReader.reads, 4);
    });

    test('propagates definitive reader failures immediately', () async {
      statusReader = FakeStatusReader(<Object?>[
        const NoriaCheckoutException(
          NoriaCheckoutErrorCode.sessionUnavailable,
          'A sessão de pagamento não está disponível.',
        ),
      ]);
      controller = build();

      await expectLater(
        open(),
        throwsCheckoutError(NoriaCheckoutErrorCode.sessionUnavailable),
      );
      expect(statusReader.reads, 1);
    });

    test('the return link still wins while polling is idle', () async {
      statusReader = FakeStatusReader(
        <Object?>[],
        NoriaCheckoutSessionStatus.open,
      );
      controller = build(pollInterval: const Duration(minutes: 5));
      final Future<NoriaCheckoutResult?> pending = open();
      await pumpEventQueue();
      expect(statusReader.reads, 1);

      appLinks.emit(returnLinkFor(session()));
      final NoriaCheckoutResult? result = await pending;
      expect(result?.returnUri, returnLinkFor(session()));
    });

    test('stops polling once the session expires', () async {
      DateTime current = now;
      statusReader = FakeStatusReader(
        <Object?>[],
        NoriaCheckoutSessionStatus.open,
      );
      controller = NoriaCheckoutController(
        appLinks: appLinks,
        launcher: launcher,
        statusReader: statusReader,
        clock: () => current,
        pollInterval: Duration.zero,
      );
      final Future<NoriaCheckoutResult?> pending = open();
      await pumpEventQueue();
      current = session().expiresAt.add(const Duration(seconds: 1));

      await expectLater(
        pending,
        throwsCheckoutError(NoriaCheckoutErrorCode.returnTimeout),
      );
    });
  });

  group('cancellation', () {
    test('a newer open cancels the pending one', () async {
      final Completer<NoriaCheckoutSessionStatus?> firstRead =
          Completer<NoriaCheckoutSessionStatus?>();
      statusReader = FakeStatusReader(<Object?>[
        firstRead.future,
        NoriaCheckoutSessionStatus.completed,
      ]);
      controller = build();

      final Future<NoriaCheckoutResult?> stale = open();
      final Future<void> staleExpectation = expectLater(
        stale,
        throwsA(isA<NoriaCheckoutCancelledException>()),
      );
      await pumpEventQueue();
      expect(controller.hasPending, isTrue);

      final NoriaCheckoutResult? latest = await open();
      firstRead.complete(NoriaCheckoutSessionStatus.open);

      expect(latest?.sessionId, sessionId);
      await staleExpectation;
      expect(launcher.launched, hasLength(2));
      expect(appLinks.hasListener, isFalse);
      expect(controller.hasPending, isFalse);
    });

    test('cancelPending fails the wait and is a no-op afterwards', () async {
      final Future<NoriaCheckoutResult?> pending = open();
      await pumpEventQueue();
      expect(controller.hasPending, isTrue);

      controller.cancelPending();
      await expectLater(
        pending,
        throwsCheckoutError(NoriaCheckoutErrorCode.cancelled),
      );
      expect(appLinks.hasListener, isFalse);
      expect(controller.hasPending, isFalse);

      controller.cancelPending();
      expect(controller.hasPending, isFalse);
    });

    test('a stale completed status never resolves the newer wait', () async {
      final Completer<NoriaCheckoutSessionStatus?> firstRead =
          Completer<NoriaCheckoutSessionStatus?>();
      statusReader = FakeStatusReader(<Object?>[firstRead.future]);
      controller = build();

      final Future<NoriaCheckoutResult?> stale = open();
      final Future<void> staleExpectation = expectLater(
        stale,
        throwsA(isA<NoriaCheckoutCancelledException>()),
      );
      await pumpEventQueue();

      final Future<NoriaCheckoutResult?> latest = open();
      await pumpEventQueue();
      firstRead.complete(NoriaCheckoutSessionStatus.completed);
      await pumpEventQueue();
      await staleExpectation;
      expect(controller.hasPending, isTrue);

      appLinks.emit(returnLinkFor(session()));
      expect((await latest)?.returnUri, returnLinkFor(session()));
    });
  });

  test('can be reused for consecutive sessions', () async {
    for (int i = 0; i < 2; i++) {
      final Future<NoriaCheckoutResult?> pending = open();
      await pumpEventQueue();
      appLinks.emit(returnLinkFor(session()));
      expect((await pending)?.sessionId, sessionId);
    }
    expect(launcher.launched, hasLength(2));
    expect(appLinks.hasListener, isFalse);
  });
}
