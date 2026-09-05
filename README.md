# noria_checkout

SDK Flutter oficial do **Noria Checkout** hospedado. Abre o Checkout em um
navegador seguro da plataforma e verifica o universal/app link que traz o
cliente de volta ao aplicativo.

| Plataforma | Apresentação `inAppBrowser`   | Apresentação `redirect` | Retorno ao app                 |
| ---------- | ----------------------------- | ----------------------- | ------------------------------ |
| Android    | Chrome Custom Tabs            | Navegador padrão        | Android App Link (`autoVerify`) |
| iOS        | `SFSafariViewController`      | Safari                  | Universal Link                 |
| Web        | Nova aba                      | Redirect na mesma aba   | Página de retorno do merchant  |

## Sumário

- [Requisitos](#requisitos)
- [Instalação](#instalação)
- [Configuração de plataforma](#configuração-de-plataforma)
- [Uso](#uso)
- [Modelo de segurança](#modelo-de-segurança)
- [Tratamento de erros](#tratamento-de-erros)
- [Flutter Web](#flutter-web)
- [Testes no app hospedeiro](#testes-no-app-hospedeiro)
- [Referência da API](#referência-da-api)
- [Versionamento e suporte](#versionamento-e-suporte)

## Requisitos

- Flutter `>= 3.38.1` e Dart `>= 3.10.0`.
- Android `minSdk 21+`; iOS 12+.
- Um backend do merchant que crie a sessão de Checkout com a chave privada do
  projeto. **A chave nunca entra no aplicativo.**

## Instalação

O SDK é distribuído de forma privada via git. Fixe sempre uma tag:

```yaml
dependencies:
  noria_checkout:
    git:
      url: https://github.com/noriapay/noria-checkout-flutter.git
      ref: v1.0.0
```

```bash
flutter pub get
```

## Configuração de plataforma

O retorno do Checkout usa um **link verificado** (`https://`), nunca um
custom scheme genérico. Isso impede que outro aplicativo instalado capture o
retorno.

### Android

1. Adicione o intent filter à `MainActivity` em
   `android/app/src/main/AndroidManifest.xml`:

   ```xml
   <intent-filter android:autoVerify="true">
       <action android:name="android.intent.action.VIEW" />
       <category android:name="android.intent.category.DEFAULT" />
       <category android:name="android.intent.category.BROWSABLE" />
       <data android:scheme="https"
             android:host="app.example"
             android:pathPrefix="/payment/return" />
   </intent-filter>
   ```

2. Publique `https://app.example/.well-known/assetlinks.json` com o
   `sha256_cert_fingerprints` da chave de assinatura de produção.

3. Mantenha `android:launchMode="singleTop"` (ou `singleTask`) para que o link
   chegue à instância já aberta do app.

### iOS

1. Em Xcode, habilite **Associated Domains** e adicione
   `applinks:app.example`.
2. Publique `https://app.example/.well-known/apple-app-site-association`
   incluindo o caminho `/payment/return`.

### Web

Nenhuma configuração extra. Veja [Flutter Web](#flutter-web) para o fluxo de
retorno.

## Uso

```dart
import 'package:noria_checkout/noria_checkout.dart';

NoriaCheckoutButton(
  createSession: () async {
    final Map<String, Object?> json = await api.post('/checkout/session');
    return NoriaCheckoutSession.fromJson(json);
  },
  expectedCheckoutOrigin: Uri.parse('https://checkout.noriapay.com.br'),
  returnUrl: Uri.parse('https://app.example/payment/return'),
  onComplete: (NoriaCheckoutResult result) {
    // Confirme o status com o seu backend antes de liberar o pedido.
    orders.confirm(result.sessionId);
  },
  onError: (Object error, StackTrace stackTrace) {
    logger.warning('Checkout falhou', error, stackTrace);
  },
  child: const NoriaCheckoutButtonLabel(),
)
```

`NoriaCheckoutButtonLabel` renderiza apenas a palavra **Noria** como wordmark
oficial; o prefixo herda fonte e cor do `DefaultTextStyle` do app. O botão usa
o `FilledButtonTheme` do tema, ou o `style` informado.

### Sem o botão

Para integrar em um fluxo próprio, use o controller diretamente:

```dart
final NoriaCheckoutController checkout = NoriaCheckoutController();

final NoriaCheckoutResult? result = await checkout.open(
  session: session,
  expectedCheckoutOrigin: Uri.parse('https://checkout.noriapay.com.br'),
  returnUrl: Uri.parse('https://app.example/payment/return'),
  presentation: NoriaCheckoutPresentation.inAppBrowser,
);
```

### Contrato da sessão

`createSession` deve devolver o contrato público emitido pelo backend:

```json
{
  "sessionId": "8d3f4e0a-1b2c-4d5e-8f90-1a2b3c4d5e6f",
  "checkoutUrl": "https://checkout.noriapay.com.br/session/8d3f4e0a-1b2c-4d5e-8f90-1a2b3c4d5e6f",
  "clientSecret": "…",
  "expiresAt": "2026-09-04T18:00:00Z",
  "returnState": "…"
}
```

`id` é aceito como alias de `sessionId`. `expiresAt` deve ser ISO-8601 e é
normalizado para UTC.

## Modelo de segurança

O SDK aplica todas as verificações abaixo antes de abrir o navegador e antes
de aceitar um retorno. Qualquer falha lança `NoriaCheckoutException`; retornos
inválidos são ignorados silenciosamente.

**Ao abrir**

- `sessionId` é um UUID v4; `clientSecret` e `returnState` têm tamanho sadio.
- A sessão não está expirada.
- `expectedCheckoutOrigin` é uma origem `https` "nua" (sem caminho, query,
  fragmento ou user info).
- `checkoutUrl` tem exatamente essa origem, aponta para
  `/session/<sessionId>` e não contém query, fragmento nem user info.
- `clientSecret` vai **apenas no fragmento** da URL, que o navegador nunca
  envia pela rede.
- `returnUrl` é `https` sem query, fragmento ou user info.

**Ao retornar**

- Esquema, host, porta e caminho iguais ao `returnUrl`.
- A query contém exatamente `noria_checkout_session` e `state`, uma vez cada.
- `sessionId` e `state` conferem com a sessão aberta, em comparação de tempo
  constante.

**O que o SDK não faz**

- `onComplete` **não é** confirmação de pagamento. O status canônico deve vir
  de um webhook assinado ou de consulta server-to-server pelo `sessionId`.
- Nenhuma credencial Noria é embutida no app. `http://` só é aceito em
  `localhost`/`127.0.0.1` para desenvolvimento.

Reporte vulnerabilidades conforme [SECURITY.md](SECURITY.md).

## Tratamento de erros

Toda falha é uma `NoriaCheckoutException` com um `code` estável; use-o em vez
de inspecionar `message`, que pode mudar entre versões.

| `NoriaCheckoutErrorCode` | Quando ocorre                                                 |
| ------------------------ | ------------------------------------------------------------- |
| `malformedSession`       | JSON do backend sem campo obrigatório ou com tipo errado      |
| `invalidSessionId`       | `sessionId` não é UUID v4                                     |
| `invalidClientSecret`    | Tamanho inválido                                              |
| `invalidReturnState`     | Tamanho inválido                                              |
| `sessionExpired`         | `expiresAt` já passou                                         |
| `insecureUrl`            | URL sem `https`, com user info, query ou fragmento indevidos  |
| `originMismatch`         | `checkoutUrl` fora de `expectedCheckoutOrigin`                |
| `urlMismatch`            | Caminho de `checkoutUrl` não corresponde à sessão             |
| `launchFailed`           | Navegador não abriu (ver `cause`) ou stream de links falhou   |
| `returnTimeout`          | Sessão expirou antes do retorno verificado                    |

```dart
onError: (Object error, StackTrace stackTrace) {
  if (error is NoriaCheckoutException) {
    switch (error.code) {
      case NoriaCheckoutErrorCode.returnTimeout:
      case NoriaCheckoutErrorCode.sessionExpired:
        showRetry();
      case NoriaCheckoutErrorCode.launchFailed:
        showNoBrowser();
      default:
        report(error);
    }
  }
}
```

## Flutter Web

Uma nova aba não devolve um resultado autenticável para a `Future`, portanto
`open` retorna `null` e `onComplete` não é chamado. A página de retorno do
merchant deve validar o link e consultar o backend:

```dart
final Uri current = Uri.base;
if (isVerifiedCheckoutReturn(
  current,
  expectedReturnUrl: Uri.parse('https://app.example/payment/return'),
  session: sessionSalvaAntesDeAbrir,
)) {
  await api.confirm(sessionSalvaAntesDeAbrir.sessionId);
}
```

Persista a sessão (por exemplo em `sessionStorage`) antes de abrir o Checkout
para poder validá-la na volta. O mesmo helper serve para tratar *cold start*
no mobile, quando o app foi encerrado enquanto o cliente estava no Checkout.

## Testes no app hospedeiro

Todos os colaboradores do controller são injetáveis, então o fluxo pode ser
testado sem dispositivo:

```dart
class FakeLauncher implements NoriaCheckoutLauncher {
  @override
  Future<bool> launch(Uri url, NoriaCheckoutPresentation presentation) async => true;

  @override
  Future<void> closeInAppBrowser() async {}
}

final NoriaCheckoutController controller = NoriaCheckoutController(
  appLinks: fakeAppLinks,          // Stream<Uri> controlado pelo teste
  launcher: FakeLauncher(),
  clock: () => DateTime.utc(2026, 9, 4),
);
```

Veja `test/` neste repositório para exemplos completos.

## Referência da API

| Símbolo                                              | Descrição                                                         |
| ---------------------------------------------------- | ----------------------------------------------------------------- |
| `NoriaCheckoutButton`                                | Botão Material que cria a sessão e abre o Checkout                |
| `NoriaCheckoutButtonLabel`                           | Rótulo "Pagar com a Noria" com o wordmark oficial                 |
| `NoriaCheckoutController`                            | Abre o Checkout e aguarda o retorno verificado                    |
| `NoriaCheckoutLauncher`                              | Abstração do navegador; `NoriaCheckoutLauncher.platform()` é o padrão |
| `NoriaCheckoutSession`                               | Contrato da sessão (`fromJson`, igualdade por valor, segredos redigidos) |
| `NoriaCheckoutResult`                                | Retorno verificado com `sessionId` e `returnUri`                  |
| `NoriaCheckoutPresentation`                          | `inAppBrowser` ou `redirect`                                      |
| `NoriaCheckoutException` / `NoriaCheckoutErrorCode`  | Erro tipado com código estável e `cause`                          |
| `verifiedCheckoutUri`, `isVerifiedCheckoutReturn`    | Verificações de abertura e retorno                                |
| `isSecureCheckoutUri`, `constantTimeEquals`          | Helpers de segurança                                              |
| `noriaCheckoutSdkVersion`                            | Versão do SDK para telemetria e suporte                           |

A documentação completa é gerada com `dart doc`.

## Versionamento e suporte

- SemVer. Mudanças incompatíveis só em versão *major* e listadas no
  [CHANGELOG](CHANGELOG.md).
- Versões suportadas: a *major* atual. Correções de segurança podem ser
  retroportadas para a *major* anterior por 6 meses.
- Contribuições internas: veja [CONTRIBUTING.md](CONTRIBUTING.md).
- Licença: [Apache 2.0](LICENSE).
