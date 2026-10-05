# WhatsApp erro 131049 — "healthy ecosystem engagement"

## Sintoma
Template enviado a um contato fica com "Falha ao enviar" e o tooltip mostra
`131049: This message was not delivered to maintain healthy ecosystem engagement.`

## Investigação (2026-10-05, produção)
- Caso: conta 3, inbox 4 ("WhatsApp - ANA", `whatsapp_cloud`), template `ola_tudo_bem` (MARKETING),
  contato novo que mandou só "bom dia" na véspera; template enviado >24h depois (janela fechada).
- O Chatwit enviou normalmente. A rejeição veio da Meta no webhook de status
  (`status: failed`, `errors[0].code: 131049`). Os dois reenvios manuais também falharam com o mesmo código.
- Saúde do lado Meta (Graph API, somente leitura): número com qualidade GREEN, `LIVE`, throughput STANDARD;
  WABA `APPROVED` e verificada, `can_send_message: AVAILABLE`; template `APPROVED`, sem `rejected_reason`.
- Frequência: 1 ocorrência em todo o banco. Em 60 dias, 5 de 6 templates MARKETING foram entregues
  (inclusive `ola_tudo_bem` em 14/09, 23/09 e 01/10).

## Causa raiz
Decisão da Meta por destinatário (limite/engajamento de templates de marketing). Não é bug do Chatwit nem
problema de número, template ou conta. Não há como contornar do nosso lado.

## O que mudou
`components-next/message/MessageError.vue` passa a exibir uma explicação localizada quando o erro vem como
`<codigo>: <titulo>` e existe a chave `CONVERSATION.EXTERNAL_ERRORS.CODE_<codigo>` (hoje só `CODE_131049`,
em `en` e `pt_BR`). Sem chave, mostra o texto cru da Meta como antes. O tooltip também passou de `break-all`
para `break-words` para não quebrar palavras no meio.

Para cobrir outro código no futuro, basta adicionar `CODE_<codigo>` em `conversation.json`.

## Para o atendimento
Reenviar na hora não resolve. Esperar o contato responder (abre a janela de 24h e libera texto livre) ou
usar um template de categoria UTILITY quando o conteúdo realmente for utilitário.
