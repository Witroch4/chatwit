# Captain Payment Phase 2 — Operação (Chatwit)

Feature: revisão de pagamento one-shot pelo Captain, acordada exclusivamente pela etiqueta
`captain_revisar_pagamento`. Contrato completo: `witdev-platform-core/docs/contrato-plataforma-unificada.md`
(Contrato 6). Spec/emenda: `witdev-platform-core/docs/superpowers/specs/`.

## Como ativar

1. **Super Admin → Accounts → conta alvo**: botão "Captain Payment Phase 2" (grava
   `internal_attributes['captain_payment_phase2']`). Alternativa operacional por ENV:
   `CAPTAIN_PAYMENT_PHASE2_ENABLED=true` + `CAPTAIN_PAYMENT_PHASE2_INBOX_IDS=<ids>`.
2. **Vínculo Captain↔Inbox** da inbox WhatsApp alvo em modo `phase2_only` (a fase 1 nunca
   dispara o Captain contínuo nesse modo).
3. **Config do vínculo** (form do Captain, campos fase 2):
   - **Modelo LLM** (`phase2_model`): select alimentado por `GET .../captain/llm_models`
     (fonte canônica: `Chatwit::LlmProxy.catalog_models` → platform-api `/api/v1/llm/models`;
     nunca catálogo próprio). Vazio ⇒ cadeia padrão da instalação.
   - **Prompt** (`phase2_prompt`): abre pré-preenchido com o padrão
     (`Captain::PaymentReview::DEFAULT_PROMPT`); editável. Instruções extras do operador
     (ex.: enviar CNPJ/e-mail para Pix manual) entram aqui — valores citados verbatim no
     prompt são os ÚNICOS que o validador permite em replies.
   - **Favoritos autorizados** (`phase2_payment_preset_ids`): quais `payment_presets` o
     Captain pode enviar via `send_payment_preset` (valor/descrição/template resolvidos
     server-side; o LLM só escolhe o id).
4. A etiqueta é provisionada automaticamente (boot + criação de conta).

## Ciclo de vida

- Fase 1 (Socialwise) cria a cobrança, envia o CTA e aplica a etiqueta (Platform Bot,
  `/labels/add`, com correlação do contexto financeiro).
- A borda de subida cria um trigger durável (geração) e um run com lease; a posse do
  Socialwise é cercada imediatamente.
- O run consulta o contexto sanitizado da Platform, decide via schema fechado e finaliza
  atomicamente: pago ⇒ silêncio + reconciliação; sem dúvida ⇒ silêncio; dúvida ⇒ no máx.
  1 resposta/ação oficial (CTA/Pix/status via envelope TTL 30s, ou favorito autorizado);
  fora do escopo ⇒ handoff humano (único ramo que abre espera).
- Novo ciclo: remover e reaplicar a etiqueta. Resolver a conversa devolve a posse ao
  Socialwise.

## Pagamentos

- Confirmação SOMENTE via `payment_check` oficial InfinitePay (receipt
  `infinitepay_payment_check`). O webhook `/webhooks/infinitepay` apenas enfileira o evento;
  o worker verifica e o reconciler aplica milestones retomáveis (link, mensagem de
  confirmação, push, forwards Socialwise/JusMonitorIA) sem duplicar em crash/retry.

## ENVs

Ver tabela do Contrato 6. Essenciais: `CAPTAIN_PAYMENT_PLATFORM_URL`,
`CHATWIT_WEBHOOK_SECRET`, `CAPTAIN_WITDEV_PROXY_URL`/`CAPTAIN_WITDEV_PROXY_API_KEY`/
`CAPTAIN_LLM_ROUTE=witdev`, `CAPTAIN_PAYMENT_PHASE2_MAX_ATTEMPTS`.

## Kill-switch / rollback / troubleshooting

- Desativar (flag/ENV) bloqueia novos claims; runs ativos drenam (a posse não volta ao
  Socialwise no meio de um run). Rollback completo: remover o nó do flow → drenar runs →
  desativar → reverter endpoints.
- Falhas do run: label mantida + nota privada sanitizada na conversa
  (`conversations.captain.payment_review_note`); corrigir a causa e remover+reaplicar a
  etiqueta para novo ciclo.
- Auditoria: `captain_payment_review_triggers` (gerações), `captain_payment_review_runs`
  (lease/outcome/reason), `infinitepay_webhook_events` (inbox), `payment_reconciliations`
  (milestones).
