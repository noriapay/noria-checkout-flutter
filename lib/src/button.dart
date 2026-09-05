import 'package:flutter/material.dart';

import 'controller.dart';
import 'presentation.dart';
import 'result.dart';
import 'session.dart';

/// Creates a Checkout session on the merchant backend.
///
/// Must call the merchant server, never Noria directly: the project's private
/// key stays on the server side.
typedef NoriaCreateSession = Future<NoriaCheckoutSession> Function();

/// Receives the verified return of a Checkout session.
typedef NoriaCheckoutCallback = void Function(NoriaCheckoutResult result);

/// Receives any failure raised while creating or opening a session.
typedef NoriaCheckoutErrorCallback =
    void Function(Object error, StackTrace stackTrace);

/// A Material button that creates a session and opens the hosted Checkout.
///
/// The button disables itself while a session is being created or the
/// customer is inside the Checkout, so a double tap cannot open two sessions.
/// Styling comes from the ambient [FilledButtonTheme] unless [style] is set.
class NoriaCheckoutButton extends StatefulWidget {
  /// Creates a Checkout button.
  const NoriaCheckoutButton({
    required this.createSession,
    required this.expectedCheckoutOrigin,
    required this.returnUrl,
    required this.child,
    this.onComplete,
    this.onError,
    this.controller,
    this.presentation = NoriaCheckoutPresentation.inAppBrowser,
    this.enabled = true,
    this.style,
    this.loadingIndicator,
    this.semanticLabel = 'Abrir Noria Checkout',
    super.key,
  });

  /// Creates the session on the merchant backend when the button is tapped.
  final NoriaCreateSession createSession;

  /// The only origin the Checkout is allowed to load from, for example
  /// `https://checkout.noriapay.com.br`.
  final Uri expectedCheckoutOrigin;

  /// The universal/app link the Checkout redirects to when finished.
  final Uri returnUrl;

  /// Content of the button. Use [NoriaCheckoutButtonLabel] for the official
  /// branding.
  final Widget child;

  /// Called with the verified return. Not called on Flutter Web.
  final NoriaCheckoutCallback? onComplete;

  /// Called when creating the session or opening the Checkout fails.
  final NoriaCheckoutErrorCallback? onError;

  /// Controller used to open the Checkout. When omitted, the button owns one.
  final NoriaCheckoutController? controller;

  /// How the Checkout is presented.
  final NoriaCheckoutPresentation presentation;

  /// Whether the button reacts to taps.
  final bool enabled;

  /// Overrides the ambient [FilledButtonTheme].
  final ButtonStyle? style;

  /// Replaces the default progress indicator shown while busy.
  final Widget? loadingIndicator;

  /// Accessibility label announced by screen readers.
  final String semanticLabel;

  @override
  State<NoriaCheckoutButton> createState() => _NoriaCheckoutButtonState();
}

class _NoriaCheckoutButtonState extends State<NoriaCheckoutButton> {
  bool _busy = false;
  NoriaCheckoutController? _ownedController;

  NoriaCheckoutController get _controller =>
      widget.controller ?? (_ownedController ??= NoriaCheckoutController());

  Future<void> _open() async {
    if (_busy || !widget.enabled) {
      return;
    }
    setState(() => _busy = true);
    try {
      final NoriaCheckoutSession session = await widget.createSession();
      final NoriaCheckoutResult? result = await _controller.open(
        session: session,
        expectedCheckoutOrigin: widget.expectedCheckoutOrigin,
        returnUrl: widget.returnUrl,
        presentation: widget.presentation,
      );
      if (result != null && mounted) {
        widget.onComplete?.call(result);
      }
    } on Object catch (error, stackTrace) {
      if (mounted) {
        widget.onError?.call(error, stackTrace);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool active = widget.enabled && !_busy;
    // MergeSemantics folds [semanticLabel] into the button's own semantics
    // node, so assistive technologies announce one focusable button carrying
    // both the label and the tap action. The visual child is excluded so a
    // wordmark image or a busy indicator never leaks into the announcement.
    return MergeSemantics(
      child: Semantics(
        label: widget.semanticLabel,
        child: FilledButton(
          style: widget.style,
          onPressed: active ? _open : null,
          child: ExcludeSemantics(
            child: _busy
                ? (widget.loadingIndicator ?? const _DefaultLoadingIndicator())
                : widget.child,
          ),
        ),
      ),
    );
  }
}

class _DefaultLoadingIndicator extends StatelessWidget {
  const _DefaultLoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

/// The official "Pagar com a Noria" label.
///
/// Only the word *Noria* is rendered as the brand wordmark; [prefix] inherits
/// the ambient [DefaultTextStyle] so the label blends with the host app.
class NoriaCheckoutButtonLabel extends StatelessWidget {
  /// Creates the label with an optional custom [prefix].
  const NoriaCheckoutButtonLabel({this.prefix = 'Pagar com a ', super.key});

  /// Text placed before the Noria wordmark.
  final String prefix;

  /// Height of the wordmark in logical pixels.
  static const double wordmarkHeight = 16;

  @override
  Widget build(BuildContext context) {
    final TextStyle inherited = DefaultTextStyle.of(context).style;
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(prefix, style: inherited),
          Image.asset(
            'assets/images/noria-wordmark.png',
            package: 'noria_checkout',
            height: wordmarkHeight,
            fit: BoxFit.contain,
            color: inherited.color,
            colorBlendMode: BlendMode.srcIn,
          ),
        ],
      ),
    );
  }
}
