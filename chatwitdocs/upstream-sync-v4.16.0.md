# Upstream sync Chatwoot 4.16.0

Data: 2026-07-18

## Escopo

O Chatwit foi atualizado da base Chatwoot 4.13 para o commit de release 4.16.0
`a752e56765a46bb62571932fe6bebf0b71b31b61` por meio de um merge Git real. O
merge absorve 405 commits upstream e preserva o histórico dos dois projetos.

Foram resolvidos manualmente 76 conflitos. Os 28 conflitos binários de ícones e
favicons mantiveram os assets Chatwit byte a byte; os demais foram combinados por
domínio, sem escolher em massa um dos lados.

## Captain e fluxo canônico de LLM

A rota `CAPTAIN_LLM_ROUTE=witdev` agora cobre todos os 10 recursos generativos
publicados em `config/llm.yml`:

- `editor`
- `assistant`
- `copilot`
- `label_suggestion`
- `document_faq_generation`
- `conversation_faq_generation`
- `pdf_faq_generation`
- `help_center_article_generation`
- `onboarding_content_generation`
- `help_center_query_translation`

Todos usam exclusivamente o catálogo canônico do `platform-api` para seleção e
o `platform-litellm` para execução. O alias salvo por conta tem precedência sobre
`CAPTAIN_WITDEV_MODEL`; catálogo ou alias não operacional falha fechado e nunca
cai em credenciais ou modelos legados.

`audio_transcription` e `help_center_search` continuam explicitamente no fluxo
legado do Chatwoot. Embeddings, OpenAI Files API e Whisper nativo também não foram
movidos para o proxy WitDev.

## Customizações preservadas

- bot global `Chatwit::PlatformBot` e allowlist do Agent Bot;
- SocialWise Flow, debounce, respostas sync/async, Lead Sync e rich messages;
- JusMonitorIA, eventos, assinatura HMAC e ações;
- QUICK_REPLY e templates em WhatsApp, Instagram e Facebook;
- Evolution Go como provider de WhatsApp;
- Payment Phase 2 e seu modelo canônico por inbox;
- PWA mobile isolada do desktop, Web Push/VAPID e haptic feedback;
- branding, manifest, favicons e ícones do Chatwit;
- infraestrutura compartilhada de PostgreSQL e Redis.

## Validação

- baseline anterior ao merge: 189 exemplos Ruby e 11 testes frontend;
- conflitos resolvidos: 125 exemplos Ruby;
- matriz LLM/Captain: 197 exemplos Ruby;
- todos os caminhos Enterprise Captain: 1.077 exemplos Ruby;
- funcionalidades fork-only: 746 exemplos Ruby em 59 arquivos;
- frontend focado: 24 testes Vitest;
- RuboCop focado nos arquivos LLM/Captain sem infrações;
- ESLint focado nos arquivos Vue/JavaScript alterados sem infrações;
- migrações executadas do zero em PostgreSQL e schema comparado semanticamente.

## Regra para próximas alterações

Antes de modificar qualquer fluxo LLM, consultar
`/home/wital/witdev-platform-core/docs/LLM-CANONICAL-FLOW-ALL-APPS.md`.
`platform-litellm` continua como autoridade de modelos e roteamento, e
`platform-api /api/v1/llm/models` continua sendo o único contrato de listagem
para apps.
