import 'package:flutter_test/flutter_test.dart';
import 'package:noria_checkout/noria_checkout.dart';

import 'support/fixtures.dart';

void main() {
  group('verifiedCheckoutUri', () {
    Uri verify(NoriaCheckoutSession value, {Uri? origin, DateTime? at}) {
      return verifiedCheckoutUri(
        value,
        expectedCheckoutOrigin: origin ?? checkoutOrigin,
        now: at ?? now,
      );
    }

    test('places the client secret only in the fragment', () {
      final Uri value = verify(session());
      expect(value.query, isEmpty);
      expect(value.fragment, 'client_secret=${session().clientSecret}');
      expect(value.origin, checkoutOrigin.origin);
      expect(value.path, '/session/$sessionId');
    });

    test('allows http on localhost for local development', () {
      final Uri origin = Uri.parse('http://localhost:3000');
      final Uri value = verify(
        session(checkoutUrl: 'http://localhost:3000/session/$sessionId'),
        origin: origin,
      );
      expect(value.host, 'localhost');
    });

    test('uses the wall clock when now is omitted', () {
      expect(
        () => verifiedCheckoutUri(
          session(expiresAt: DateTime.utc(2000)),
          expectedCheckoutOrigin: checkoutOrigin,
        ),
        throwsCheckoutError(NoriaCheckoutErrorCode.sessionExpired),
      );
    });

    final Map<String, (NoriaCheckoutSession, NoriaCheckoutErrorCode)>
    cases = <String, (NoriaCheckoutSession, NoriaCheckoutErrorCode)>{
      'a non UUID v4 sessionId': (
        session(id: 'not-a-uuid'),
        NoriaCheckoutErrorCode.invalidSessionId,
      ),
      'a UUID that is not version 4': (
        session(id: '11111111-1111-1111-8111-111111111111'),
        NoriaCheckoutErrorCode.invalidSessionId,
      ),
      'a short clientSecret': (
        session(clientSecret: 'short'),
        NoriaCheckoutErrorCode.invalidClientSecret,
      ),
      'an oversized clientSecret': (
        session(clientSecret: 'x' * 257),
        NoriaCheckoutErrorCode.invalidClientSecret,
      ),
      'a short returnState': (
        session(returnState: 'short'),
        NoriaCheckoutErrorCode.invalidReturnState,
      ),
      'an expired session': (
        session(expiresAt: now),
        NoriaCheckoutErrorCode.sessionExpired,
      ),
      'an insecure remote Checkout host': (
        session(checkoutUrl: 'http://evil.example/session/$sessionId'),
        NoriaCheckoutErrorCode.insecureUrl,
      ),
      'a relative checkoutUrl': (
        session(checkoutUrl: '/session/$sessionId'),
        NoriaCheckoutErrorCode.insecureUrl,
      ),
      'user info inside checkoutUrl': (
        session(
          checkoutUrl:
              'https://user:pw@checkout.development.noriapay.com.br/session/$sessionId',
        ),
        NoriaCheckoutErrorCode.insecureUrl,
      ),
      'a Checkout URL from another origin': (
        session(
          checkoutUrl: 'https://checkout.noriapay.com.br/session/$sessionId',
        ),
        NoriaCheckoutErrorCode.originMismatch,
      ),
      'a different port on the same host': (
        session(
          checkoutUrl:
              'https://checkout.development.noriapay.com.br:8443/session/$sessionId',
        ),
        NoriaCheckoutErrorCode.originMismatch,
      ),
      'a path that does not match the session': (
        session(
          checkoutUrl:
              '${checkoutOrigin.origin}/session/22222222-2222-4222-8222-222222222222',
        ),
        NoriaCheckoutErrorCode.urlMismatch,
      ),
      'a path with a trailing segment': (
        session(checkoutUrl: '${checkoutOrigin.origin}/session/$sessionId/x'),
        NoriaCheckoutErrorCode.urlMismatch,
      ),
      'a query string on checkoutUrl': (
        session(checkoutUrl: '${checkoutOrigin.origin}/session/$sessionId?x=1'),
        NoriaCheckoutErrorCode.insecureUrl,
      ),
      'the client secret in the query string': (
        session(
          checkoutUrl:
              '${checkoutOrigin.origin}/session/$sessionId?client_secret=abc',
        ),
        NoriaCheckoutErrorCode.insecureUrl,
      ),
      'a fragment on checkoutUrl': (
        session(checkoutUrl: '${checkoutOrigin.origin}/session/$sessionId#f'),
        NoriaCheckoutErrorCode.insecureUrl,
      ),
    };

    cases.forEach((
      String description,
      (NoriaCheckoutSession, NoriaCheckoutErrorCode) c,
    ) {
      test('rejects $description', () {
        expect(() => verify(c.$1), throwsCheckoutError(c.$2));
      });
    });

    for (final String origin in <String>[
      'http://checkout.development.noriapay.com.br',
      'https://checkout.development.noriapay.com.br/path',
      'https://checkout.development.noriapay.com.br/?q=1',
      'https://checkout.development.noriapay.com.br/#frag',
      'https://u:p@checkout.development.noriapay.com.br',
    ]) {
      test('rejects the expected origin "$origin"', () {
        expect(
          () => verify(session(), origin: Uri.parse(origin)),
          throwsCheckoutError(NoriaCheckoutErrorCode.insecureUrl),
        );
      });
    }
  });

  group('isVerifiedCheckoutReturn', () {
    final NoriaCheckoutSession value = session();

    bool check(Uri link, {Uri? expected}) {
      return isVerifiedCheckoutReturn(
        link,
        expectedReturnUrl: expected ?? returnUrl,
        session: value,
      );
    }

    test('accepts the genuine return link', () {
      expect(check(returnLinkFor(value)), isTrue);
    });

    test('accepts parameters in any order', () {
      expect(
        check(
          Uri.parse(
            '$returnUrl?state=${value.returnState}&noria_checkout_session=$sessionId',
          ),
        ),
        isTrue,
      );
    });

    test('accepts http on localhost during development', () {
      final Uri local = Uri.parse('http://localhost:8080/return');
      expect(check(returnLinkFor(value, base: local), expected: local), isTrue);
    });

    final Map<String, String> rejected = <String, String>{
      'a forged state':
          '$returnUrl?noria_checkout_session=$sessionId&state=attacker-state-value',
      'another session id':
          '$returnUrl?noria_checkout_session=22222222-2222-4222-8222-222222222222&state=${value.returnState}',
      'an extra parameter':
          '$returnUrl?noria_checkout_session=$sessionId&state=${value.returnState}&extra=1',
      'a missing state': '$returnUrl?noria_checkout_session=$sessionId',
      'a duplicated state':
          '$returnUrl?noria_checkout_session=$sessionId&state=${value.returnState}&state=${value.returnState}',
      'another host':
          'https://evil.example/payment/return?noria_checkout_session=$sessionId&state=${value.returnState}',
      'another scheme':
          'http://shop.example/payment/return?noria_checkout_session=$sessionId&state=${value.returnState}',
      'another port':
          'https://shop.example:8443/payment/return?noria_checkout_session=$sessionId&state=${value.returnState}',
      'another path':
          'https://shop.example/payment/return/../x?noria_checkout_session=$sessionId&state=${value.returnState}',
      'a fragment':
          '$returnUrl?noria_checkout_session=$sessionId&state=${value.returnState}#x',
      'user info':
          'https://a:b@shop.example/payment/return?noria_checkout_session=$sessionId&state=${value.returnState}',
      'a state that is only a prefix':
          '$returnUrl?noria_checkout_session=$sessionId&state=state-with-enough',
    };

    rejected.forEach((String description, String link) {
      test('rejects $description', () {
        expect(check(Uri.parse(link)), isFalse);
      });
    });

    for (final String expected in <String>[
      'http://shop.example/payment/return',
      'https://shop.example/payment/return?x=1',
      'https://shop.example/payment/return#x',
      'https://u:p@shop.example/payment/return',
    ]) {
      test(
        'rejects everything when the expected URL "$expected" is unsafe',
        () {
          final Uri base = Uri.parse(expected);
          expect(
            check(returnLinkFor(value, base: base), expected: base),
            isFalse,
          );
        },
      );
    }
  });

  group('helpers', () {
    test('constantTimeEquals compares exact bytes', () {
      expect(constantTimeEquals('abc', 'abc'), isTrue);
      expect(constantTimeEquals('abc', 'abd'), isFalse);
      expect(constantTimeEquals('abc', 'ab'), isFalse);
      expect(constantTimeEquals('', ''), isTrue);
      expect(constantTimeEquals('é', 'e'), isFalse);
    });

    test('isSecureCheckoutUri accepts https and loopback http only', () {
      expect(isSecureCheckoutUri(Uri.parse('https://a.example')), isTrue);
      expect(isSecureCheckoutUri(Uri.parse('http://localhost:3000')), isTrue);
      expect(isSecureCheckoutUri(Uri.parse('http://127.0.0.1')), isTrue);
      expect(isSecureCheckoutUri(Uri.parse('http://a.example')), isFalse);
      expect(isSecureCheckoutUri(Uri.parse('ftp://localhost')), isFalse);
      expect(isSecureCheckoutUri(Uri.parse('myapp://return')), isFalse);
    });
  });
}
