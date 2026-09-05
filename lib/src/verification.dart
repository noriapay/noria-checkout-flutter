import 'dart:convert';

import 'exception.dart';
import 'session.dart';

/// Query parameter that carries the session identifier on the return URL.
const String noriaCheckoutSessionParameter = 'noria_checkout_session';

/// Query parameter that carries the anti-forgery state on the return URL.
const String noriaCheckoutStateParameter = 'state';

final RegExp _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// Whether [value] may carry a Checkout secret: `https`, or `http` restricted
/// to loopback hosts for local development.
bool isSecureCheckoutUri(Uri value) {
  if (value.scheme == 'https') {
    return true;
  }
  return value.scheme == 'http' &&
      (value.host == 'localhost' || value.host == '127.0.0.1');
}

/// Compares two strings in time independent of where they first differ.
///
/// Used for secrets such as `state` so a network-observable timing difference
/// cannot be used to guess the expected value byte by byte.
bool constantTimeEquals(String a, String b) {
  final List<int> left = utf8.encode(a);
  final List<int> right = utf8.encode(b);
  int difference = left.length ^ right.length;
  final int length = left.length < right.length ? left.length : right.length;
  for (int i = 0; i < length; i++) {
    difference |= left[i] ^ right[i];
  }
  return difference == 0;
}

bool _isBareOrigin(Uri value) =>
    isSecureCheckoutUri(value) &&
    value.userInfo.isEmpty &&
    (value.path.isEmpty || value.path == '/') &&
    !value.hasQuery &&
    !value.hasFragment;

bool _sameOrigin(Uri a, Uri b) =>
    a.scheme == b.scheme && a.host == b.host && a.port == b.port;

/// Validates [session] against [expectedCheckoutOrigin] and returns the URI
/// that must be opened in the browser.
///
/// The returned URI carries `clientSecret` exclusively in the fragment, which
/// browsers never send over the network. Throws a [NoriaCheckoutException]
/// when any invariant fails:
///
/// * `sessionId` must be a UUID v4;
/// * `clientSecret` and `returnState` must have sane lengths;
/// * the session must not be expired at [now] (defaults to the current time);
/// * [expectedCheckoutOrigin] must be a bare `https` origin;
/// * `checkoutUrl` must share that origin, point to `/session/<sessionId>` and
///   contain no query, fragment or user info.
Uri verifiedCheckoutUri(
  NoriaCheckoutSession session, {
  required Uri expectedCheckoutOrigin,
  DateTime? now,
}) {
  if (!_uuidV4.hasMatch(session.sessionId)) {
    throw const NoriaCheckoutException(
      NoriaCheckoutErrorCode.invalidSessionId,
      'sessionId inválido.',
    );
  }
  if (session.clientSecret.length < 20 || session.clientSecret.length > 256) {
    throw const NoriaCheckoutException(
      NoriaCheckoutErrorCode.invalidClientSecret,
      'clientSecret inválido.',
    );
  }
  if (session.returnState.length < 16 || session.returnState.length > 256) {
    throw const NoriaCheckoutException(
      NoriaCheckoutErrorCode.invalidReturnState,
      'returnState inválido.',
    );
  }
  final DateTime reference = (now ?? DateTime.now()).toUtc();
  if (!session.expiresAt.toUtc().isAfter(reference)) {
    throw const NoriaCheckoutException(
      NoriaCheckoutErrorCode.sessionExpired,
      'A sessão expirou.',
    );
  }
  if (!_isBareOrigin(expectedCheckoutOrigin)) {
    throw const NoriaCheckoutException(
      NoriaCheckoutErrorCode.insecureUrl,
      'expectedCheckoutOrigin deve ser uma origem https sem caminho, '
      'query ou fragmento.',
    );
  }
  final Uri? uri = Uri.tryParse(session.checkoutUrl);
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
    throw const NoriaCheckoutException(
      NoriaCheckoutErrorCode.insecureUrl,
      'checkoutUrl não é uma URL absoluta.',
    );
  }
  if (!isSecureCheckoutUri(uri) || uri.userInfo.isNotEmpty) {
    throw const NoriaCheckoutException(
      NoriaCheckoutErrorCode.insecureUrl,
      'checkoutUrl insegura.',
    );
  }
  if (!_sameOrigin(uri, expectedCheckoutOrigin)) {
    throw const NoriaCheckoutException(
      NoriaCheckoutErrorCode.originMismatch,
      'Origem do Checkout não autorizada.',
    );
  }
  if (uri.path != '/session/${session.sessionId}') {
    throw const NoriaCheckoutException(
      NoriaCheckoutErrorCode.urlMismatch,
      'checkoutUrl não corresponde à sessão.',
    );
  }
  if (uri.hasQuery || uri.hasFragment) {
    throw const NoriaCheckoutException(
      NoriaCheckoutErrorCode.insecureUrl,
      'checkoutUrl não pode conter query ou fragmento.',
    );
  }
  return uri.replace(fragment: 'client_secret=${session.clientSecret}');
}

/// Whether [value] is the genuine return link for [session].
///
/// All of the following must hold, otherwise the link is ignored:
///
/// * [expectedReturnUrl] is a secure URL without user info, query or fragment;
/// * [value] has the same scheme, host, port and path as [expectedReturnUrl]
///   and carries no user info or fragment;
/// * the query contains exactly `noria_checkout_session` and `state`, once
///   each, matching [NoriaCheckoutSession.sessionId] and
///   [NoriaCheckoutSession.returnState].
///
/// Use it on Flutter Web return pages and when handling cold-start links
/// outside [NoriaCheckoutController].
bool isVerifiedCheckoutReturn(
  Uri value, {
  required Uri expectedReturnUrl,
  required NoriaCheckoutSession session,
}) {
  if (!isSecureCheckoutUri(expectedReturnUrl) ||
      expectedReturnUrl.userInfo.isNotEmpty ||
      expectedReturnUrl.hasQuery ||
      expectedReturnUrl.hasFragment) {
    return false;
  }
  if (value.userInfo.isNotEmpty ||
      value.hasFragment ||
      !_sameOrigin(value, expectedReturnUrl) ||
      value.path != expectedReturnUrl.path) {
    return false;
  }
  final Map<String, List<String>> parameters = value.queryParametersAll;
  if (parameters.length != 2) {
    return false;
  }
  final List<String>? sessionIds = parameters[noriaCheckoutSessionParameter];
  final List<String>? states = parameters[noriaCheckoutStateParameter];
  if (sessionIds == null ||
      states == null ||
      sessionIds.length != 1 ||
      states.length != 1) {
    return false;
  }
  final bool sessionMatches = constantTimeEquals(
    sessionIds.single,
    session.sessionId,
  );
  final bool stateMatches = constantTimeEquals(
    states.single,
    session.returnState,
  );
  return sessionMatches & stateMatches;
}

/// Public status endpoint for [session] on [expectedCheckoutOrigin].
///
/// The client secret is never part of this URL; it travels in a header.
Uri checkoutStatusUri(
  NoriaCheckoutSession session, {
  required Uri expectedCheckoutOrigin,
}) {
  return Uri(
    scheme: expectedCheckoutOrigin.scheme,
    host: expectedCheckoutOrigin.host,
    port: expectedCheckoutOrigin.hasPort ? expectedCheckoutOrigin.port : null,
    path: '/v1/public/checkout-session/${session.sessionId}',
  );
}
