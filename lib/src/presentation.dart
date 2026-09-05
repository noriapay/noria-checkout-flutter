/// How the hosted Checkout is presented to the customer.
enum NoriaCheckoutPresentation {
  /// Chrome Custom Tabs on Android, `SFSafariViewController` on iOS and a
  /// new tab on Flutter Web. The customer stays inside the merchant app.
  inAppBrowser,

  /// The default external browser on mobile and a same-tab redirect on
  /// Flutter Web.
  redirect,
}
