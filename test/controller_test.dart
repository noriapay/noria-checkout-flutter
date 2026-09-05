import 'package:flutter_test/flutter_test.dart';
import 'package:noria_checkout/noria_checkout.dart';

import 'support/fixtures.dart';

void main() {
  late FakeAppLinks appLinks;
  late FakeLauncher launcher;
  late NoriaCheckoutController controller;

  setUp(() {
    appLinks = FakeAppLinks();
    launcher = FakeLauncher();
    controller = NoriaCheckoutController(
      appLinks: appLinks,
      launcher: launcher,
      clock: () => now,
    );
  });

  tearDown(() => appLinks.dispose());

  Future<NoriaCheckoutResult?> open({
    NoriaCheckoutSession? value,
    Uri? origin,
    Uri? back,
    NoriaCheckoutPresentation presentation =
        NoriaCheckoutPresentation.inAppBrowser,
  }) {
    return controller.open(
      session: value ?? session(),
      expectedCheckoutOrigin: origin ?? checkoutOrigin,
      returnUrl: back ?? returnUrl,
      presentation: presentation,
    );
  }

  test('opens the verified URI and completes on the genuine return', () async {
    final Future<NoriaCheckoutResult?> pending = open();
    await pumpEventQueue();

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
    await expectLater(
      open(),
      throwsCheckoutError(NoriaCheckoutErrorCode.launchFailed),
    );
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
    controller = NoriaCheckoutController(
      appLinks: appLinks,
      launcher: launcher,
      clock: () => now,
      maxWait: const Duration(milliseconds: 100),
    );
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
    expect(
      () => NoriaCheckoutController(
        appLinks: appLinks,
        launcher: launcher,
        maxWait: Duration.zero,
      ),
      throwsAssertionError,
    );
  });

  test('exposes the default maxWait', () {
    expect(controller.maxWait, NoriaCheckoutController.defaultMaxWait);
    expect(NoriaCheckoutController.defaultMaxWait, const Duration(hours: 24));
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
