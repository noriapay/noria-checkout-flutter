import 'package:flutter/foundation.dart';

/// Emitted when a verified return link for a Checkout session reaches the app.
///
/// This is **not** a payment confirmation. The canonical payment status must
/// come from a signed webhook or a server-to-server query using [sessionId].
@immutable
class NoriaCheckoutResult {
  /// Creates a result for [sessionId] that arrived through [returnUri].
  const NoriaCheckoutResult({required this.sessionId, required this.returnUri});

  /// Identifier of the session the customer returned from.
  final String sessionId;

  /// The verified universal/app link that brought the customer back.
  final Uri returnUri;

  @override
  bool operator ==(Object other) =>
      other is NoriaCheckoutResult &&
      other.sessionId == sessionId &&
      other.returnUri == returnUri;

  @override
  int get hashCode => Object.hash(sessionId, returnUri);

  @override
  String toString() => 'NoriaCheckoutResult(sessionId: $sessionId)';
}
