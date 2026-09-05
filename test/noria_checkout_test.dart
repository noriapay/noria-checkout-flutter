import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noria_checkout/noria_checkout.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

NoriaCheckoutSession session({String? checkoutUrl}) {
  return NoriaCheckoutSession(
    sessionId: '11111111-1111-4111-8111-111111111111',
    checkoutUrl: checkoutUrl ??
        'https://checkout.development.noriapay.com.br/session/11111111-1111-4111-8111-111111111111',
    clientSecret: 'secret-with-at-least-twenty-characters',
    expiresAt: DateTime.utc(2026, 9, 2, 15),
    returnState: 'state-with-enough-entropy',
  );
}

NoriaCheckoutSession activeSession() {
  return NoriaCheckoutSession(
    sessionId: '11111111-1111-4111-8111-111111111111',
    checkoutUrl:
        'https://checkout.development.noriapay.com.br/session/11111111-1111-4111-8111-111111111111',
    clientSecret: 'secret-with-at-least-twenty-characters',
    expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    returnState: 'state-with-enough-entropy',
  );
}

class _PendingController extends NoriaCheckoutController {
  final Completer<NoriaCheckoutResult?> result =
      Completer<NoriaCheckoutResult?>();

  @override
  Future<NoriaCheckoutResult?> open({
    required NoriaCheckoutSession session,
    required Uri expectedCheckoutOrigin,
    required Uri returnUrl,
    NoriaCheckoutPresentation presentation =
        NoriaCheckoutPresentation.inAppBrowser,
    VoidCallback? onOpened,
  }) {
    onOpened?.call();
    return result.future;
  }
}

void main() {
  test('places the client secret only in the fragment', () {
    final Uri value = verifiedCheckoutUri(
      session(),
      expectedCheckoutOrigin:
          Uri.parse('https://checkout.development.noriapay.com.br'),
      now: DateTime.utc(2026, 9, 2, 14),
    );
    expect(value.query, isEmpty);
    expect(
      value.fragment,
      'client_secret=secret-with-at-least-twenty-characters',
    );
  });

  test('rejects insecure remote Checkout hosts', () {
    expect(
      () => verifiedCheckoutUri(
        session(
          checkoutUrl:
              'http://evil.example/session/11111111-1111-4111-8111-111111111111',
        ),
        expectedCheckoutOrigin:
            Uri.parse('https://checkout.development.noriapay.com.br'),
        now: DateTime.utc(2026, 9, 2, 14),
      ),
      throwsA(isA<NoriaCheckoutException>()),
    );
  });

  test('rejects a Checkout URL from another environment', () {
    expect(
      () => verifiedCheckoutUri(
        session(),
        expectedCheckoutOrigin: Uri.parse('https://checkout.noriapay.com.br'),
        now: DateTime.utc(2026, 9, 2, 14),
      ),
      throwsA(isA<NoriaCheckoutException>()),
    );
  });

  test('verifies return endpoint, session and state together', () {
    final NoriaCheckoutSession value = session();
    const String returnBase = 'https://shop.example/payment/return';
    expect(
      isVerifiedCheckoutReturn(
        Uri.parse(
          '$returnBase?noria_checkout_session=${value.sessionId}&state=${value.returnState}',
        ),
        expectedReturnUrl: Uri.parse(returnBase),
        session: value,
      ),
      isTrue,
    );
    expect(
      isVerifiedCheckoutReturn(
        Uri.parse(
          '$returnBase?noria_checkout_session=${value.sessionId}&state=attacker-state-value',
        ),
        expectedReturnUrl: Uri.parse(returnBase),
        session: value,
      ),
      isFalse,
    );
    expect(
      isVerifiedCheckoutReturn(
        Uri.parse(
          '$returnBase?noria_checkout_session=${value.sessionId}&state=${value.returnState}&extra=1',
        ),
        expectedReturnUrl: Uri.parse(returnBase),
        session: value,
      ),
      isFalse,
    );
    expect(
      isVerifiedCheckoutReturn(
        Uri.parse(
          'https://evil.example/payment/return?noria_checkout_session=${value.sessionId}&state=${value.returnState}',
        ),
        expectedReturnUrl: Uri.parse(returnBase),
        session: value,
      ),
      isFalse,
    );
  });

  testWidgets('brands only Noria in the button label',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: NoriaCheckoutButtonLabel()),
      ),
    );

    expect(find.text('Pagar com a '), findsOneWidget);
    final Image brand = tester.widget<Image>(find.byType(Image));
    expect(brand.semanticLabel, isNull);
    expect(brand.height, 16);
  });

  testWidgets('stops loading after the Checkout browser opens',
      (WidgetTester tester) async {
    final _PendingController controller = _PendingController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoriaCheckoutButton(
            controller: controller,
            createSession: () async => session(),
            expectedCheckoutOrigin:
                Uri.parse('https://checkout.development.noriapay.com.br'),
            returnUrl: Uri.parse('https://shop.example/payment/return'),
            child: const Text('Pagar'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Pagar'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    final FilledButton button = tester.widget<FilledButton>(
      find.byType(FilledButton),
    );
    expect(button.onPressed, isNotNull);

    controller.result.complete(null);
    await tester.pump();
  });

  test('completes UX from the canonical public session status', () async {
    Uri? requestedStatusUrl;
    String? suppliedSecret;
    int statusReads = 0;
    bool opened = false;
    bool closed = false;
    final NoriaCheckoutController controller = NoriaCheckoutController(
      appLinkStream: const Stream<Uri>.empty(),
      launcher: (
        Uri uri, {
        required LaunchMode mode,
        String? webOnlyWindowName,
      }) async {
        opened = true;
        return true;
      },
      statusReader: (Uri statusUrl, String clientSecret) async {
        requestedStatusUrl = statusUrl;
        suppliedSecret = clientSecret;
        return statusReads++ == 0 ? 'open' : 'completed';
      },
      closer: () async => closed = true,
      pollInterval: Duration.zero,
    );

    final NoriaCheckoutResult? result = await controller.open(
      session: activeSession(),
      expectedCheckoutOrigin:
          Uri.parse('https://checkout.development.noriapay.com.br'),
      returnUrl: Uri.parse('https://shop.example/payment/return'),
    );

    expect(result?.sessionId, activeSession().sessionId);
    expect(
      requestedStatusUrl,
      Uri.parse(
        'https://checkout.development.noriapay.com.br/v1/public/checkout-session/${activeSession().sessionId}',
      ),
    );
    expect(requestedStatusUrl?.query, isEmpty);
    expect(requestedStatusUrl?.fragment, isEmpty);
    expect(suppliedSecret, activeSession().clientSecret);
    expect(opened, isTrue);
    expect(closed, isTrue);
  });

  test('delegates terminal session rendering to the hosted Checkout', () async {
    final List<String> events = <String>[];
    bool opened = false;
    bool closed = false;
    final NoriaCheckoutController controller = NoriaCheckoutController(
      appLinkStream: const Stream<Uri>.empty(),
      launcher: (
        Uri uri, {
        required LaunchMode mode,
        String? webOnlyWindowName,
      }) async {
        events.add('launch');
        opened = true;
        return true;
      },
      statusReader: (Uri statusUrl, String clientSecret) async {
        events.add('status');
        return 'completed';
      },
      closer: () async => closed = true,
      pollInterval: Duration.zero,
    );

    final NoriaCheckoutResult? result = await controller.open(
      session: activeSession(),
      expectedCheckoutOrigin:
          Uri.parse('https://checkout.development.noriapay.com.br'),
      returnUrl: Uri.parse('https://shop.example/payment/return'),
    );

    expect(result?.sessionId, activeSession().sessionId);
    expect(opened, isTrue);
    expect(closed, isTrue);
    expect(events, <String>['launch', 'status']);
  });

  test('cancels a stale open while its status poll is in flight', () async {
    final Completer<String?> firstStatus = Completer<String?>();
    int statusReads = 0;
    int launches = 0;
    final NoriaCheckoutController controller = NoriaCheckoutController(
      appLinkStream: const Stream<Uri>.empty(),
      launcher: (
        Uri uri, {
        required LaunchMode mode,
        String? webOnlyWindowName,
      }) async {
        launches++;
        return true;
      },
      statusReader: (Uri statusUrl, String clientSecret) {
        if (statusReads++ == 0) return firstStatus.future;
        return Future<String?>.value('completed');
      },
      closer: () async {},
      pollInterval: Duration.zero,
    );

    final Future<NoriaCheckoutResult?> staleOpen = controller.open(
      session: activeSession(),
      expectedCheckoutOrigin:
          Uri.parse('https://checkout.development.noriapay.com.br'),
      returnUrl: Uri.parse('https://shop.example/payment/return'),
    );
    final Future<void> staleExpectation = expectLater(
      staleOpen,
      throwsA(isA<NoriaCheckoutCancelledException>()),
    );
    await Future<void>.delayed(Duration.zero);

    final NoriaCheckoutResult? latestResult = await controller.open(
      session: activeSession(),
      expectedCheckoutOrigin:
          Uri.parse('https://checkout.development.noriapay.com.br'),
      returnUrl: Uri.parse('https://shop.example/payment/return'),
    );
    firstStatus.complete('open');

    expect(latestResult?.sessionId, activeSession().sessionId);
    await staleExpectation;
    expect(launches, 2);
  });

  test('bounds failures while polling the public session status', () async {
    int attempts = 0;
    final NoriaCheckoutController controller = NoriaCheckoutController(
      appLinkStream: const Stream<Uri>.empty(),
      launcher: (Uri uri,
              {required LaunchMode mode, String? webOnlyWindowName}) async =>
          true,
      statusReader: (Uri statusUrl, String clientSecret) async {
        attempts++;
        throw StateError('synthetic network failure');
      },
      closer: () async {},
      pollInterval: Duration.zero,
      maxConsecutivePollFailures: 2,
    );

    await expectLater(
      controller.open(
        session: activeSession(),
        expectedCheckoutOrigin:
            Uri.parse('https://checkout.development.noriapay.com.br'),
        returnUrl: Uri.parse('https://shop.example/payment/return'),
      ),
      throwsA(
        isA<NoriaCheckoutException>().having(
          (NoriaCheckoutException error) => error.message,
          'message',
          'Não foi possível acompanhar a confirmação do pagamento.',
        ),
      ),
    );
    expect(attempts, 2);
  });
}
