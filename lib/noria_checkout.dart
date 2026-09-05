/// Noria hosted Checkout for Flutter.
///
/// The SDK opens the hosted Checkout in a platform browser and waits for the
/// verified universal/app link that brings the customer back:
///
/// ```dart
/// NoriaCheckoutButton(
///   createSession: () async =>
///       NoriaCheckoutSession.fromJson(await api.post('/checkout')),
///   expectedCheckoutOrigin: Uri.parse('https://checkout.noriapay.com.br'),
///   returnUrl: Uri.parse('https://app.example/payment/return'),
///   onComplete: (result) => confirmWithBackend(result.sessionId),
///   child: const NoriaCheckoutButtonLabel(),
/// )
/// ```
///
/// Secrets never leave the merchant backend: `createSession` calls the
/// merchant server, and the payment status must be confirmed through a signed
/// webhook or a server-to-server query.
library;

export 'src/button.dart';
export 'src/controller.dart';
export 'src/exception.dart';
export 'src/launcher.dart';
export 'src/presentation.dart';
export 'src/result.dart';
export 'src/session.dart';
export 'src/verification.dart';
export 'src/version.dart';
