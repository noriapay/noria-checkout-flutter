import 'dart:convert';

import 'package:http/http.dart' as http;

import 'exception.dart';
import 'session_status.dart';

/// Reads the public state of a Checkout session.
///
/// The SDK ships an HTTP implementation, obtained through
/// [NoriaCheckoutStatusReader.http], that calls the public session endpoint
/// with the client secret in a header. Provide your own implementation to
/// fake the endpoint in tests.
abstract interface class NoriaCheckoutStatusReader {
  /// The default reader backed by `package:http`.
  ///
  /// [client] defaults to a fresh [http.Client]; [timeout] bounds each request.
  factory NoriaCheckoutStatusReader.http({
    http.Client? client,
    Duration timeout,
  }) = _HttpCheckoutStatusReader;

  /// Fetches the state of the session at [statusUrl], authenticating with
  /// [clientSecret].
  ///
  /// Returns `null` for a transient failure the controller may retry. Throws
  /// a [NoriaCheckoutException] with [NoriaCheckoutErrorCode.sessionUnavailable]
  /// or [NoriaCheckoutErrorCode.invalidStatus] for definitive failures.
  Future<NoriaCheckoutSessionStatus?> read(Uri statusUrl, String clientSecret);
}

/// Header that carries the client secret to the public status endpoint.
const String noriaCheckoutSecretHeader = 'X-Checkout-Secret';

class _HttpCheckoutStatusReader implements NoriaCheckoutStatusReader {
  _HttpCheckoutStatusReader({
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  @override
  Future<NoriaCheckoutSessionStatus?> read(
    Uri statusUrl,
    String clientSecret,
  ) async {
    final http.Response response = await _client
        .get(
          statusUrl,
          headers: <String, String>{
            noriaCheckoutSecretHeader: clientSecret,
            'Accept': 'application/json',
            'Cache-Control': 'no-store',
          },
        )
        .timeout(timeout);
    if (response.statusCode == 401 || response.statusCode == 404) {
      throw const NoriaCheckoutException(
        NoriaCheckoutErrorCode.sessionUnavailable,
        'A sessão de pagamento não está disponível.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (error) {
      throw NoriaCheckoutException(
        NoriaCheckoutErrorCode.invalidStatus,
        'O Checkout retornou um estado inválido.',
        cause: error,
      );
    }
    final Object? raw = decoded is Map<String, Object?>
        ? decoded['status']
        : null;
    final NoriaCheckoutSessionStatus? status = raw is String
        ? NoriaCheckoutSessionStatus.tryParse(raw)
        : null;
    if (status == null) {
      throw const NoriaCheckoutException(
        NoriaCheckoutErrorCode.invalidStatus,
        'O Checkout retornou um estado inválido.',
      );
    }
    return status;
  }
}
