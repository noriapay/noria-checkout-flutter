import 'package:flutter/foundation.dart';

/// Classifies every failure raised by the Noria Checkout SDK.
///
/// Integrators should branch on the code instead of parsing
/// [NoriaCheckoutException.message], which is a human-readable text that may
/// change between releases.
enum NoriaCheckoutErrorCode {
  /// The session payload returned by the merchant backend is malformed.
  malformedSession,

  /// The `sessionId` is not a UUID v4.
  invalidSessionId,

  /// The `clientSecret` has an invalid length.
  invalidClientSecret,

  /// The `returnState` has an invalid length.
  invalidReturnState,

  /// The session is already expired.
  sessionExpired,

  /// A URL does not use `https` (or `http` on localhost) or carries
  /// user info, query or fragment where it must not.
  insecureUrl,

  /// The Checkout URL origin does not match the expected Checkout origin.
  originMismatch,

  /// The Checkout URL path does not match the session.
  urlMismatch,

  /// The platform browser could not be opened.
  launchFailed,

  /// The session expired before a verified return link arrived.
  returnTimeout,
}

/// Exception raised by every public entry point of the SDK.
///
/// Each instance carries a stable [code] for programmatic handling and a
/// [message] intended for logs and developer diagnostics. Messages never
/// include secrets.
@immutable
class NoriaCheckoutException implements Exception {
  /// Creates an exception with a stable [code] and a diagnostic [message].
  const NoriaCheckoutException(this.code, this.message, {this.cause});

  /// Stable, machine-readable classification of the failure.
  final NoriaCheckoutErrorCode code;

  /// Human-readable description intended for logs. Never contains secrets.
  final String message;

  /// The underlying error, when the failure wraps a platform exception.
  final Object? cause;

  @override
  bool operator ==(Object other) =>
      other is NoriaCheckoutException &&
      other.code == code &&
      other.message == message;

  @override
  int get hashCode => Object.hash(code, message);

  @override
  String toString() => 'NoriaCheckoutException(${code.name}): $message';
}
