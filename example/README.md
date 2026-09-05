# Exemplo do Noria Checkout

O app mantém preço e itens no backend do merchant. Ele envia apenas `cartId`
ao endpoint de sessão configurado e recebe o contrato público da sessão.

```bash
flutter run -d chrome \
  --dart-define=NORIA_DEMO_SESSION_ENDPOINT=https://merchant.example/checkout/session \
  --dart-define=NORIA_CHECKOUT_ORIGIN=https://checkout.development.noriapay.com.br \
  --dart-define=NORIA_CHECKOUT_RETURN_URL=https://merchant.example/payment/return
```

Sem `NORIA_DEMO_SESSION_ENDPOINT`, o app roda como prévia visual sem
interação. Nunca coloque a chave privada Ed25519 do projeto ou uma chave
interna Noria em `--dart-define` ou no bundle do aplicativo.

Para testar o retorno no Android e iOS, configure o `assetlinks.json` e o
`apple-app-site-association` conforme o [README principal](../README.md).
