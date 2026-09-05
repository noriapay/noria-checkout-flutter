# Changelog

Todas as mudanças relevantes deste SDK são documentadas aqui. O formato segue
[Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e o versionamento
segue [SemVer](https://semver.org/lang/pt-BR/).

## [1.0.0] - 2026-09-04

Primeira versão estável.

### Adicionado

- `NoriaCheckoutButton` e `NoriaCheckoutButtonLabel` com a marca oficial.
- `NoriaCheckoutController` reutilizável, com `AppLinks`, `NoriaCheckoutLauncher`
  e relógio injetáveis para testes.
- `NoriaCheckoutLauncher`: abstração do navegador com implementação padrão via
  `url_launcher` (Custom Tabs, `SFSafariViewController`, nova aba na web).
- `NoriaCheckoutException` com `NoriaCheckoutErrorCode` estável para tratamento
  programático de erros e `cause` com a exceção de plataforma original.
- `NoriaCheckoutSession.fromJson` estrito: nunca lança `TypeError`, normaliza
  `expiresAt` para UTC e aceita `id` como alias de `sessionId`.
- `NoriaCheckoutResult.returnUri` com o link verificado que trouxe o cliente de
  volta.
- `verifiedCheckoutUri`, `isVerifiedCheckoutReturn`, `isSecureCheckoutUri` e
  `constantTimeEquals` públicos para páginas de retorno na web e cold start.
- `noriaCheckoutSdkVersion` para telemetria e suporte.
- Fechamento automático do navegador in-app após o retorno verificado.
- `style`, `loadingIndicator` e `semanticLabel` no botão.
- Pipeline de CI (formatação, análise com infos fatais, testes com piso de
  cobertura e build web do exemplo).
- Licença Apache 2.0.

### Alterado

- `onError` agora recebe `(Object error, StackTrace stackTrace)`.
- `returnUrl` não pode conter query nem fragmento.
- Dependência `app_links` passa a usar restrição caret (`^7.0.0`) em vez de
  versão fixa, evitando conflitos no app hospedeiro.

## [0.1.0-beta.1] - 2026-09-02

- Versão inicial interna.

[1.0.0]: https://github.com/noriapay/noria-checkout-flutter/releases/tag/v1.0.0
[0.1.0-beta.1]: https://github.com/noriapay/noria-checkout-flutter/releases/tag/v0.1.0-beta.1
