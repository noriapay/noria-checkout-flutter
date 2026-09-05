import 'package:flutter/foundation.dart';

/// Emitted when a Checkout session completes from the app's point of view:
/// either a verified return link reached the app or the public session status
/// became `completed`.
///
/// This is **not** the canonical payment confirmation. It must still come
/// from a signed webhook or a server-to-server query using [sessionId].
@immutable
class NoriaCheckoutResult {
  /// Creates a result for [sessionId] that arrived through [returnUri].
  const NoriaCheckoutResult({required this.sessionId, required this.returnUri});

  /// Identifier of the session the customer returned from.
  final String sessionId;

  /// The URI that signalled completion: the verified universal/app link, or
  /// the public status endpoint when completion came from polling.
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
