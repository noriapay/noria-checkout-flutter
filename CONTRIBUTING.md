# Contribuindo

## Ambiente

```bash
flutter pub get
cd example && flutter pub get && cd ..
```

## Antes de abrir um PR

O CI executa exatamente estes comandos; rode-os localmente:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos --fatal-warnings
flutter test --coverage
```

- Cobertura mínima de linhas: 85%.
- Todo membro público precisa de dartdoc (`public_member_api_docs`).
- Mensagens de erro nunca incluem `clientSecret` ou `returnState`.
- Mudanças na API pública exigem entrada no `CHANGELOG.md`.

## Estrutura

```
lib/
  noria_checkout.dart   # barrel público
  src/
    button.dart         # NoriaCheckoutButton e NoriaCheckoutButtonLabel
    controller.dart     # abre o Checkout e aguarda o retorno
    launcher.dart       # abstração do navegador (url_launcher por padrão)
    verification.dart   # regras de segurança de abertura e retorno
    session.dart        # contrato da sessão
    result.dart         # retorno verificado
    exception.dart      # erro tipado + códigos
    presentation.dart   # inAppBrowser | redirect
    version.dart        # noriaCheckoutSdkVersion
test/                   # espelha lib/src; fixtures em test/support/
example/                # app de demonstração
```

## Release

1. Atualize `version` em `pubspec.yaml` e `lib/src/version.dart`.
2. Adicione a seção `## [x.y.z] - AAAA-MM-DD` no `CHANGELOG.md`.
3. Abra o PR; o CI valida a consistência das três fontes.
4. Após o merge, crie a tag: `git tag -a vx.y.z -m "vx.y.z" && git push --tags`.
5. Apps consumidores fixam `ref: vx.y.z` na dependência git.
