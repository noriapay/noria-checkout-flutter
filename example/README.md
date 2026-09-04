# Noria Checkout Flutter example

The sample keeps price and line items on the merchant backend. The app sends
only `cartId` to the configured session endpoint and receives the public
Checkout session contract.

```bash
flutter run -d chrome \
  --dart-define=NORIA_DEMO_SESSION_ENDPOINT=https://merchant.example/checkout/session \
  --dart-define=NORIA_CHECKOUT_ORIGIN=https://checkout.development.noriapay.com.br \
  --dart-define=NORIA_CHECKOUT_RETURN_URL=https://merchant.example/payment/return
```

Without `NORIA_DEMO_SESSION_ENDPOINT`, the app runs as a non-interactive visual
preview. Never place the project's Ed25519 private key or a Noria internal key
in a `--dart-define` or in the application bundle.
