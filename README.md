# noria_checkout

SDK Flutter privado do Noria Checkout. No Android, abre Chrome Custom Tabs; no iOS, Safari View Controller; no Flutter Web, abre uma nova aba ou redirect.

```dart
NoriaCheckoutButton(
  createSession: () async => NoriaCheckoutSession.fromJson(
    await api.post('/checkout'),
  ),
  expectedCheckoutOrigin: Uri.parse(environment.noriaCheckoutOrigin),
  returnUrl: Uri.parse('https://app.example/payment/return'),
  onComplete: (result) => confirmarPedido(result.sessionId),
  child: const NoriaCheckoutButtonLabel(),
)
```

`NoriaCheckoutButtonLabel` mantém apenas a palavra **Noria** como o wordmark
oficial da marca; o restante do rótulo herda a fonte e a cor do aplicativo.

O domínio e caminho do universal/app link, o `sessionId` e o `state` são verificados juntos. Configure também `apple-app-site-association` e `assetlinks.json`; não use um custom scheme genérico como único controle de retorno.

A chave Ed25519 nunca entra no aplicativo. `createSession` deve chamar o backend do cliente, e a confirmação canônica deve vir de webhook assinado ou consulta server-to-server.

No Flutter Web, abrir uma nova aba não dispara `onComplete`: a página de retorno deve validar `sessionId` e `state` com `isVerifiedCheckoutReturn` e consultar o backend. Isso evita tratar a simples abertura do Checkout como pagamento concluído.
