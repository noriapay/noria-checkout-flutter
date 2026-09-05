import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;

import 'presentation.dart';

/// Opens the hosted Checkout in a platform browser.
///
/// The SDK ships a default implementation backed by `url_launcher`, obtained
/// through [NoriaCheckoutLauncher.platform]. Provide your own implementation
/// to plug a different browser integration or to fake the browser in tests.
abstract interface class NoriaCheckoutLauncher {
  /// The default launcher backed by `url_launcher`.
  factory NoriaCheckoutLauncher.platform() = _UrlLauncherCheckoutLauncher;

  /// Opens [url] using [presentation].
  ///
  /// Returns `false` when the platform reports that no browser could be
  /// opened. May throw a platform exception, which the controller converts
  /// into a `NoriaCheckoutException`.
  Future<bool> launch(Uri url, NoriaCheckoutPresentation presentation);

  /// Closes the in-app browser opened by [launch], when the platform supports
  /// it. Must never throw.
  Future<void> closeInAppBrowser();
}

class _UrlLauncherCheckoutLauncher implements NoriaCheckoutLauncher {
  @override
  Future<bool> launch(Uri url, NoriaCheckoutPresentation presentation) {
    if (kIsWeb) {
      return url_launcher.launchUrl(
        url,
        webOnlyWindowName: presentation == NoriaCheckoutPresentation.redirect
            ? '_self'
            : '_blank',
      );
    }
    return url_launcher.launchUrl(
      url,
      mode: presentation == NoriaCheckoutPresentation.redirect
          ? url_launcher.LaunchMode.externalApplication
          : url_launcher.LaunchMode.inAppBrowserView,
    );
  }

  @override
  Future<void> closeInAppBrowser() async {
    if (kIsWeb) {
      return;
    }
    try {
      final bool supported = await url_launcher.supportsCloseForLaunchMode(
        url_launcher.LaunchMode.inAppBrowserView,
      );
      if (supported) {
        await url_launcher.closeInAppWebView();
      }
    } on Object {
      // Closing the browser is best effort: the verified return already
      // happened and the customer is back in the app.
    }
  }
}
