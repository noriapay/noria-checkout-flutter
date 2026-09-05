/// Public lifecycle state of a hosted Checkout session.
enum NoriaCheckoutSessionStatus {
  /// The customer has not finished paying yet.
  open('open'),

  /// The payment is being processed by the acquirer.
  processing('processing'),

  /// The payment was confirmed. This is the only successful terminal state.
  completed('completed'),

  /// The session expired before the payment completed.
  expired('expired'),

  /// The customer or the merchant cancelled the session.
  cancelled('cancelled'),

  /// The payment was refused or failed.
  failed('failed');

  const NoriaCheckoutSessionStatus(this.wireValue);

  /// Value used by the public session status endpoint.
  final String wireValue;

  /// Whether the session can no longer change state.
  bool get isTerminal => this != open && this != processing;

  /// Parses a wire value, returning `null` for unknown states so callers can
  /// treat them as a contract violation.
  static NoriaCheckoutSessionStatus? tryParse(String value) {
    for (final NoriaCheckoutSessionStatus status in values) {
      if (status.wireValue == value) {
        return status;
      }
    }
    return null;
  }
}
