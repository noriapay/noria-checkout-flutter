import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noria_checkout/noria_checkout.dart';

/// A valid UUID v4 used across the suite.
const String sessionId = '11111111-1111-4111-8111-111111111111';

/// Origin of the Checkout used across the suite.
final Uri checkoutOrigin = Uri.parse(
  'https://checkout.development.noriapay.com.br',
);

/// Return URL registered as a universal/app link.
final Uri returnUrl = Uri.parse('https://shop.example/payment/return');

/// Fixed "now" so expiry checks are deterministic.
final DateTime now = DateTime.utc(2026, 9, 2, 14);

/// Builds a valid session, optionally overriding individual fields.
NoriaCheckoutSession session({
  String? id,
  String? checkoutUrl,
  String? clientSecret,
  DateTime? expiresAt,
  String? returnState,
}) {
  final String resolvedId = id ?? sessionId;
  return NoriaCheckoutSession(
    sessionId: resolvedId,
    checkoutUrl: checkoutUrl ?? '${checkoutOrigin.origin}/session/$resolvedId',
    clientSecret: clientSecret ?? 'secret-with-at-least-twenty-characters',
    expiresAt: expiresAt ?? DateTime.utc(2026, 9, 2, 15),
    returnState: returnState ?? 'state-with-enough-entropy',
  );
}

/// The genuine return link for [value].
Uri returnLinkFor(NoriaCheckoutSession value, {Uri? base}) {
  return (base ?? returnUrl).replace(
    queryParameters: <String, String>{
      noriaCheckoutSessionParameter: value.sessionId,
      noriaCheckoutStateParameter: value.returnState,
    },
  );
}

/// Matches a [NoriaCheckoutException] with the given [code].
Matcher throwsCheckoutError(NoriaCheckoutErrorCode code) {
  return throwsA(
    isA<NoriaCheckoutException>().having((e) => e.code, 'code', code),
  );
}

/// Fake universal link source driven by tests.
class FakeAppLinks extends Fake implements AppLinks {
  final StreamController<Uri> links = StreamController<Uri>.broadcast();

  @override
  Stream<Uri> get uriLinkStream => links.stream;

  /// Whether any listener is currently attached to [uriLinkStream].
  bool get hasListener => links.hasListener;

  void emit(Uri link) => links.add(link);

  void fail(Object error) => links.addError(error);

  Future<void> dispose() => links.close();
}

/// Fake browser that records what the controller asked it to do.
class FakeLauncher implements NoriaCheckoutLauncher {
  FakeLauncher({this.opened = true, this.error});

  bool opened;
  Object? error;
  final List<Uri> launched = <Uri>[];
  final List<NoriaCheckoutPresentation> presentations =
      <NoriaCheckoutPresentation>[];
  int closeCalls = 0;

  @override
  Future<bool> launch(Uri url, NoriaCheckoutPresentation presentation) async {
    launched.add(url);
    presentations.add(presentation);
    final Object? failure = error;
    if (failure != null) {
      throw failure;
    }
    return opened;
  }

  @override
  Future<void> closeInAppBrowser() async {
    closeCalls++;
  }
}
