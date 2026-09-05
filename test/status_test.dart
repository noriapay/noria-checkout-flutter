import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:noria_checkout/noria_checkout.dart';

import 'support/fixtures.dart';

void main() {
  final Uri statusUrl = Uri.parse(
    '${checkoutOrigin.origin}/v1/public/checkout-session/$sessionId',
  );

  group('NoriaCheckoutSessionStatus', () {
    test('parses every wire value and rejects unknown ones', () {
      for (final NoriaCheckoutSessionStatus status
          in NoriaCheckoutSessionStatus.values) {
        expect(NoriaCheckoutSessionStatus.tryParse(status.wireValue), status);
      }
      expect(NoriaCheckoutSessionStatus.tryParse('paid'), isNull);
      expect(NoriaCheckoutSessionStatus.tryParse('COMPLETED'), isNull);
    });

    test('flags terminal states', () {
      expect(NoriaCheckoutSessionStatus.open.isTerminal, isFalse);
      expect(NoriaCheckoutSessionStatus.processing.isTerminal, isFalse);
      expect(NoriaCheckoutSessionStatus.completed.isTerminal, isTrue);
      expect(NoriaCheckoutSessionStatus.expired.isTerminal, isTrue);
      expect(NoriaCheckoutSessionStatus.cancelled.isTerminal, isTrue);
      expect(NoriaCheckoutSessionStatus.failed.isTerminal, isTrue);
    });
  });

  group('checkoutStatusUri', () {
    test('targets the public endpoint without secrets', () {
      final Uri value = checkoutStatusUri(
        session(),
        expectedCheckoutOrigin: checkoutOrigin,
      );
      expect(value, statusUrl);
      expect(value.hasQuery, isFalse);
      expect(value.hasFragment, isFalse);
      expect(value.toString(), isNot(contains(session().clientSecret)));
    });

    test('keeps an explicit port', () {
      final Uri value = checkoutStatusUri(
        session(),
        expectedCheckoutOrigin: Uri.parse('http://localhost:3000'),
      );
      expect(
        value.toString(),
        'http://localhost:3000/v1/public/checkout-session/$sessionId',
      );
    });
  });

  group('NoriaCheckoutStatusReader.http', () {
    NoriaCheckoutStatusReader reader(
      Future<http.Response> Function(http.Request request) handler,
    ) {
      return NoriaCheckoutStatusReader.http(client: MockClient(handler));
    }

    test('sends the secret in a header and parses the status', () async {
      http.Request? seen;
      final NoriaCheckoutSessionStatus? status = await reader((
        http.Request request,
      ) async {
        seen = request;
        return http.Response(
          jsonEncode(<String, String>{'status': 'processing'}),
          200,
        );
      }).read(statusUrl, 'secret-with-at-least-twenty-characters');

      expect(status, NoriaCheckoutSessionStatus.processing);
      expect(seen?.method, 'GET');
      expect(seen?.url, statusUrl);
      expect(
        seen?.headers[noriaCheckoutSecretHeader],
        'secret-with-at-least-twenty-characters',
      );
      expect(seen?.headers['Cache-Control'], 'no-store');
      expect(seen?.url.toString(), isNot(contains('secret')));
    });

    for (final int code in <int>[401, 404]) {
      test('treats HTTP $code as sessionUnavailable', () async {
        await expectLater(
          reader(
            (http.Request request) async => http.Response('', code),
          ).read(statusUrl, 'secret'),
          throwsCheckoutError(NoriaCheckoutErrorCode.sessionUnavailable),
        );
      });
    }

    for (final int code in <int>[500, 502, 429]) {
      test('treats HTTP $code as a transient failure', () async {
        expect(
          await reader(
            (http.Request request) async => http.Response('', code),
          ).read(statusUrl, 'secret'),
          isNull,
        );
      });
    }

    for (final String body in <String>[
      'not json',
      '[]',
      '{}',
      '{"status": 1}',
      '{"status": "paid"}',
    ]) {
      test('rejects the body $body as invalidStatus', () async {
        await expectLater(
          reader(
            (http.Request request) async => http.Response(body, 200),
          ).read(statusUrl, 'secret'),
          throwsCheckoutError(NoriaCheckoutErrorCode.invalidStatus),
        );
      });
    }

    test('propagates network errors so the controller can retry', () async {
      await expectLater(
        reader(
          (http.Request request) async => throw http.ClientException('down'),
        ).read(statusUrl, 'secret'),
        throwsA(isA<http.ClientException>()),
      );
    });
  });

  group('exceptions', () {
    test('cancelled exception carries the cancelled code', () {
      const NoriaCheckoutCancelledException error =
          NoriaCheckoutCancelledException();
      expect(error.code, NoriaCheckoutErrorCode.cancelled);
      expect(error, const NoriaCheckoutCancelledException());
      expect(
        error,
        isNot(
          const NoriaCheckoutException(
            NoriaCheckoutErrorCode.cancelled,
            'A espera pelo retorno anterior foi cancelada.',
          ),
        ),
      );
    });

    test('status exception exposes the terminal state', () {
      final NoriaCheckoutStatusException error = NoriaCheckoutStatusException(
        NoriaCheckoutSessionStatus.failed,
      );
      expect(error.status, NoriaCheckoutSessionStatus.failed);
      expect(error.code, NoriaCheckoutErrorCode.sessionNotCompleted);
      expect(error.message, contains('failed'));
    });
  });
}
