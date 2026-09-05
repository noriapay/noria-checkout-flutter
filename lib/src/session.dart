import 'package:flutter/foundation.dart';

import 'exception.dart';

/// The public contract of a hosted Checkout session created by the merchant
/// backend.
///
/// Instances are immutable. [clientSecret] and [returnState] are redacted from
/// [toString] so they never leak into logs.
@immutable
class NoriaCheckoutSession {
  /// Creates a session from already-validated values.
  ///
  /// Prefer [NoriaCheckoutSession.fromJson] when decoding a backend response.
  const NoriaCheckoutSession({
    required this.sessionId,
    required this.checkoutUrl,
    required this.clientSecret,
    required this.expiresAt,
    required this.returnState,
  });

  /// Decodes the session contract returned by the merchant backend.
  ///
  /// Accepts either `sessionId` or `id` for the identifier. `expiresAt` must be
  /// an ISO-8601 string and is normalised to UTC. Throws a
  /// [NoriaCheckoutException] with [NoriaCheckoutErrorCode.malformedSession]
  /// when a field is missing or has the wrong type.
  factory NoriaCheckoutSession.fromJson(Map<String, Object?> json) {
    final String sessionId = _requireString(
      json,
      'sessionId',
      fallbackKey: 'id',
    );
    final String checkoutUrl = _requireString(json, 'checkoutUrl');
    final String clientSecret = _requireString(json, 'clientSecret');
    final String returnState = _requireString(json, 'returnState');
    final String expiresAtRaw = _requireString(json, 'expiresAt');
    final DateTime? expiresAt = DateTime.tryParse(expiresAtRaw);
    if (expiresAt == null) {
      throw const NoriaCheckoutException(
        NoriaCheckoutErrorCode.malformedSession,
        'O campo "expiresAt" não é uma data ISO-8601 válida.',
      );
    }
    return NoriaCheckoutSession(
      sessionId: sessionId,
      checkoutUrl: checkoutUrl,
      clientSecret: clientSecret,
      expiresAt: expiresAt.toUtc(),
      returnState: returnState,
    );
  }

  /// UUID v4 that identifies the Checkout session.
  final String sessionId;

  /// Absolute URL of the hosted Checkout page for this session.
  final String checkoutUrl;

  /// Secret that authorises the browser to load the session. It is only ever
  /// placed in the URL fragment, never in the query string.
  final String clientSecret;

  /// Instant after which the session can no longer be opened, in UTC.
  final DateTime expiresAt;

  /// Opaque anti-forgery token echoed back on the return URL.
  final String returnState;

  static String _requireString(
    Map<String, Object?> json,
    String key, {
    String? fallbackKey,
  }) {
    final Object? value =
        json[key] ?? (fallbackKey == null ? null : json[fallbackKey]);
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw NoriaCheckoutException(
      NoriaCheckoutErrorCode.malformedSession,
      'O campo "$key" é obrigatório e deve ser uma string não vazia.',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NoriaCheckoutSession &&
      other.sessionId == sessionId &&
      other.checkoutUrl == checkoutUrl &&
      other.clientSecret == clientSecret &&
      other.expiresAt == expiresAt &&
      other.returnState == returnState;

  @override
  int get hashCode =>
      Object.hash(sessionId, checkoutUrl, clientSecret, expiresAt, returnState);

  @override
  String toString() =>
      'NoriaCheckoutSession(sessionId: $sessionId, checkoutUrl: $checkoutUrl, '
      'expiresAt: ${expiresAt.toIso8601String()}, '
      'clientSecret: [REDACTED], returnState: [REDACTED])';
}
