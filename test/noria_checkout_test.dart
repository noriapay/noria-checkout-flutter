import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noria_checkout/noria_checkout.dart';

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
}
