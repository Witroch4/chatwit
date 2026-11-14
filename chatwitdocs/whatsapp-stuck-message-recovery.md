# WhatsApp — Recuperação de mensagens presas em `sent`

## Problema (incidente Daniel Mourão, 17/07/2026)

O recurso `.docx` enviado automaticamente pelo painel de leads do Socialwise
("Enviar para o Chat", 06:27) **não chegou ao cliente**, mas a WhatsApp Cloud API
tinha **aceitado** a mensagem (retornou um `wamid`, sem erro). O registro ficou
eternamente em `status = sent`, sem webhook de `delivered` nem de `failed`.

Diagnóstico:
- **Não foi bug de envio do Chatwit** — a mensagem foi criada e a Meta aceitou.
- Foi uma **falha de entrega silenciosa da própria WhatsApp**. O mesmo arquivo,
  reenviado manualmente 8h depois, foi entregue normalmente.
- A janela de 24h estava OK (última mensagem do cliente ~17h30 antes).
- **Buraco nosso:** o app só reage ao webhook `failed` explícito
  (`app/services/whatsapp/incoming_message_base_service.rb`). Quando a Meta some
  depois do `sent`, nada avisava — o agente só descobriu pela reclamação.

## Solução

`app/jobs/whatsapp/stuck_message_recovery_job.rb` (agendado a cada 5 min em
`config/schedule.yml`).

Comportamento (definido com o time — "reenviar 1x, depois sinalizar"):

1. Varre mensagens **outgoing** de inboxes **whatsapp_cloud** presas em `sent`
   entre `STUCK_AFTER` (10 min) e `MAX_AGE` (6 h) de idade.
2. Primeira vez que vê a mensagem presa → **reenvia uma vez** (via
   `channel.send_message`, atualizando o `source_id` para o novo `wamid` para que
   o webhook de entrega do reenvio case com a mensagem). Marca
   `additional_attributes['stuck_recovery_resent_at']`.
3. Se, passados mais 10 min, ainda estiver em `sent` → marca como **`failed`**
   com `external_error` = `UNDELIVERED_ERROR`. Isso liga o ícone vermelho + botão de
   reenviar nativo do Chatwoot, então **o agente vê que a entrega não foi confirmada**.

### O que o agente lê (mudou em 14/11/2026)

Antes o texto dizia "Entrega não confirmada pela WhatsApp após reenvio automático. Reenvie
manualmente.", o que lia como erro do arquivo/envio e empurrava o agente a reenviar. No caso
Eliseu (#3616, 14/11/2026) a Meta **aceitou** 5 envios do mesmo `.docx` e respondeu só `sent`
(nunca `delivered` nem `failed`): o celular do contato estava desligado/sem internet, e cada
reenvio manual só aumenta as cópias que chegam juntas quando ele voltar.

Texto atual (`Whatsapp::StuckMessageRecoveryJob::UNDELIVERED_ERROR`):

> Aceita pelo WhatsApp, entrega não confirmada: o celular do contato pode estar desligado ou
> sem internet; não reenvie (pode chegar repetida) e avise o contato por outro meio.

O status continua `failed` (é ele que acende o ícone vermelho); só o texto mudou. O incidente
de 17/07 acima mostra que a Meta também pode perder a entrega de verdade: se o contato confirmar
por outro meio que não recebeu, aí sim vale reenviar.

### Salvaguardas
- Só `whatsapp_cloud` (Evolution Go/360dialog podem não reportar `delivered`).
- **Nunca** reenvia templates pagos (exclui `message_type: template` e qualquer
  mensagem com `template_payload`/`template`/`template_params`).
- Registra a tentativa **antes** de enviar → nunca há reenvio em loop, mesmo se o
  envio lançar exceção.
- `reload` antes de agir: se um webhook de entrega chegou no meio, não mexe.
- Erros por mensagem são isolados (um registro ruim não aborta o lote).

## Por que não é bug do Chatwit
A falha original foi da Meta (aceitou e não entregou). Este job apenas **fecha a
lacuna de visibilidade/retry** que era nossa: antes, uma entrega perdida ficava
invisível; agora ela é reenviada e, persistindo, sinalizada ao agente.
