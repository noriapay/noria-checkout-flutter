import 'package:flutter_test/flutter_test.dart';
import 'package:noria_checkout/noria_checkout.dart';

import 'support/fixtures.dart';

void main() {
  group('NoriaCheckoutSession.fromJson', () {
    final Map<String, Object?> payload = <String, Object?>{
      'sessionId': sessionId,
      'checkoutUrl': '${checkoutOrigin.origin}/session/$sessionId',
      'clientSecret': 'secret-with-at-least-twenty-characters',
      'expiresAt': '2026-09-02T12:00:00-03:00',
      'returnState': 'state-with-enough-entropy',
    };

    test('decodes the backend contract and normalises expiresAt to UTC', () {
      final NoriaCheckoutSession value = NoriaCheckoutSession.fromJson(payload);
      expect(value.sessionId, sessionId);
      expect(value.expiresAt.isUtc, isTrue);
      expect(value.expiresAt, DateTime.utc(2026, 9, 2, 15));
      expect(value.returnState, 'state-with-enough-entropy');
    });

    test('accepts "id" as an alias for "sessionId"', () {
      final Map<String, Object?> aliased = Map<String, Object?>.of(payload)
        ..remove('sessionId')
        ..['id'] = sessionId;
      expect(NoriaCheckoutSession.fromJson(aliased).sessionId, sessionId);
    });

    for (final String key in payload.keys) {
      test('rejects a payload without "$key"', () {
        final Map<String, Object?> broken = Map<String, Object?>.of(payload)
          ..remove(key);
        expect(
          () => NoriaCheckoutSession.fromJson(broken),
          throwsCheckoutError(NoriaCheckoutErrorCode.malformedSession),
        );
      });

      test('rejects a payload where "$key" has the wrong type', () {
        final Map<String, Object?> broken = Map<String, Object?>.of(payload)
          ..[key] = 42;
        expect(
          () => NoriaCheckoutSession.fromJson(broken),
          throwsCheckoutError(NoriaCheckoutErrorCode.malformedSession),
        );
      });
    }

    test('rejects an unparsable expiresAt', () {
      final Map<String, Object?> broken = Map<String, Object?>.of(payload)
        ..['expiresAt'] = 'tomorrow';
      expect(
        () => NoriaCheckoutSession.fromJson(broken),
        throwsCheckoutError(NoriaCheckoutErrorCode.malformedSession),
      );
    });

    test('never raises a TypeError for hostile input', () {
      expect(
        () => NoriaCheckoutSession.fromJson(const <String, Object?>{
          'sessionId': <String>[],
          'checkoutUrl': null,
        }),
        throwsA(isA<NoriaCheckoutException>()),
      );
    });
  });

  group('NoriaCheckoutSession', () {
    test('supports value equality', () {
      expect(session(), session());
      expect(session().hashCode, session().hashCode);
      expect(session(), isNot(session(returnState: 'another-state-value')));
    });

    test('redacts secrets from toString', () {
      final String printed = session().toString();
      expect(printed, contains(sessionId));
      expect(printed, isNot(contains('secret-with-at-least')));
      expect(printed, isNot(contains('state-with-enough')));
      expect(printed, contains('[REDACTED]'));
    });
  });

  group('NoriaCheckoutResult', () {
    test('supports value equality and hides nothing sensitive', () {
      final Uri link = returnLinkFor(session());
      final NoriaCheckoutResult a = NoriaCheckoutResult(
        sessionId: sessionId,
        returnUri: link,
      );
      final NoriaCheckoutResult b = NoriaCheckoutResult(
        sessionId: sessionId,
        returnUri: link,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), 'NoriaCheckoutResult(sessionId: $sessionId)');
    });
  });

  group('NoriaCheckoutException', () {
    test('exposes code, message and cause', () {
      const NoriaCheckoutException error = NoriaCheckoutException(
        NoriaCheckoutErrorCode.launchFailed,
        'boom',
        cause: 'platform',
      );
      expect(error.cause, 'platform');
      expect(error.toString(), 'NoriaCheckoutException(launchFailed): boom');
      expect(
        error.hashCode,
        const NoriaCheckoutException(
          NoriaCheckoutErrorCode.launchFailed,
          'boom',
        ).hashCode,
      );
      expect(
        error,
        isNot(
          const NoriaCheckoutException(
            NoriaCheckoutErrorCode.returnTimeout,
            'boom',
          ),
        ),
      );
      expect(
        error,
        const NoriaCheckoutException(
          NoriaCheckoutErrorCode.launchFailed,
          'boom',
        ),
      );
    });
  });
}
