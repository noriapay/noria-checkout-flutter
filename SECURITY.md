# Política de segurança

## Versões suportadas

| Versão | Suporte                       |
| ------ | ----------------------------- |
| 1.x    | Correções de segurança ativas |
| < 1.0  | Sem suporte                   |

## Reportando uma vulnerabilidade

Envie um e-mail para **admin@noriapay.com.br** com:

- descrição do problema e impacto;
- passos para reproduzir ou prova de conceito;
- versão do SDK, Flutter e plataforma afetada.

Não abra issues públicas para vulnerabilidades. Confirmamos o recebimento em
até 2 dias úteis e publicamos a correção com nota no CHANGELOG.

## Escopo

Este SDK trata exclusivamente de:

- abrir o Checkout hospedado em um navegador seguro;
- garantir que `clientSecret` nunca trafegue em query string ou logs;
- verificar que o link de retorno pertence à sessão aberta.

O status do pagamento **não** é decidido pelo app: ele deve ser confirmado por
webhook assinado ou consulta server-to-server. Chaves privadas Noria nunca
devem ser embutidas no aplicativo ou em `--dart-define`.
