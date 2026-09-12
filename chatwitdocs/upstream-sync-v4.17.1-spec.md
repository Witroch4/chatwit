# Spec — Upstream Sync Chatwoot v4.16.0 → v4.17.1

> Documento de planejamento gerado **antes** do merge, conforme a skill `chatwit-upstream-sync`.
> Data: 2026-09-12 · Branch: `develop` · Merge-base atual: `a752e56765` (v4.16.0, 2026-07-18)

---

## 1. Diagnóstico do merge-base

| Métrica | Valor |
|---------|-------|
| Merge-base | `a752e56765` — `Merge branch 'release/4.16.0' into develop` |
| Data do merge-base | 2026-07-18 |
| Commits upstream à frente (raw) | **341** (337 sem merge commits) |
| Commits nossos à frente (raw) | 382 |
| PRs upstream no intervalo | 334 |
| PRs já presentes no fork | **0** |
| PRs realmente ausentes | **334** |

**Diagnóstico:** merge-base saudável, sem *cherry-pick drift*. O sync anterior (v4.16.0) foi feito
corretamente com `git merge`. Caminho de execução: **Fase 3+ (merge normal), com cautela extra**
por se tratar de um intervalo grande (4 releases: 4.16.1, 4.16.2, 4.17.0, 4.17.1).

Composição dos 337 commits: 194 `fix`, 90 `feat`, 25 `chore`, 8 `refactor`, 8 `perf`, 3 `test`,
3 `docs`, 1 `revert`, 1 `ci`. Escopo mais movimentado: **WhatsApp (42 commits)** e **Captain (17)**.

---

## 2. Novas funcionalidades entrando no fork

### 2.1 WhatsApp — BSUID (Business-Scoped User IDs)

A maior mudança estrutural do intervalo. A Meta passou a entregar identidades com escopo de negócio
(BSUID) em vez de números de telefone em determinados fluxos. Upstream reescreveu o pipeline de
identidade do WhatsApp para suportar as duas formas convivendo no mesmo contato.

| PR | Entrega |
|----|---------|
| #15150 | Envio de mensagens para business-scoped user ids |
| #15546 | Chamadas BSUID roteadas pela identidade ativa |
| #15552 | Recuperação da informação de telefone para contatos BSUID |
| #15614 | Campanhas roteadas para destinatários BSUID |
| #15670 | Contatos BSUID classificados como leads |
| #15357 | Contatos preservados através de mudanças de ciclo de vida BSUID |
| #15630 | Conversas de telefone preservadas em payloads BSUID mistos |
| #15175 | Conversas mantidas na identidade BSUID ativa |
| #15098 | Reabertura de conversa entre identidades de coexistência |
| #14743 | Chamadas de voz de entrada com chamadores BSUID |
| #14657 | Fim dos contatos brasileiros duplicados na coexistência WhatsApp |

> **Relevância para o Chatwit:** direta. O fork depende de `incoming_message_base_service.rb`
> para extrair `extract_interactive_data` (QUICK_REPLY). O upstream refatorou esse arquivo
> (46 linhas adicionadas, 49 removidas) — é o arquivo de **maior risco** do merge.
> O fix #14657 (duplicidade de contatos BR) beneficia diretamente a operação brasileira.

### 2.2 WhatsApp — Templates, saúde e setup

| PR | Entrega |
|----|---------|
| #15277 | Message templates expostos via API |
| #15312 | Listagem de templates nas configurações |
| #15377 | Controles de listagem de template melhorados |
| #15218 | Token de gerenciamento de templates cloud |
| #15311 | Templates Twilio em cache expostos |
| #15353 | Sincronização correta do status de aprovação de templates Twilio |
| #15255 | Valores de template renderizados no transcript da conversa |
| #15199 | Coleta de parâmetros de header de texto |
| #15100 / #15550 | Monitoramento e leitura da saúde do número de telefone |
| #15079 | Setup manual guiado de inbox |
| #13539 | Orientação melhorada para finalizar a configuração do canal |
| #15626 / #15749 | Embedded signup para planos pagos / após submissão de use case |
| #15336 | Quick setup access request |
| #14938 | Suporte a descrições nas linhas de input select |
| #15279 | Respostas de flow preservadas e exibidas |

> **Relevância para o Chatwit:** alta. O fork implementa despacho de template próprio
> (`whatsapp_cloud_service.rb`, +258 linhas nossas) e uma tela de templates customizada.
> O upstream agora traz listagem nativa — precisamos garantir coexistência, não substituição.

### 2.3 Click-to-WhatsApp Ads (CTWA)

| PR | Entrega |
|----|---------|
| #14466 | Card de ad referral para leads CTWA |
| #15424 | Exibição de referrals de anúncio click-to-chat |

> **Relevância:** alta para Socialwise. Leads vindos de anúncio agora chegam com o contexto
> do criativo. Combina com o papel do Chatwit como fonte primária de leads da plataforma.

### 2.4 Captain (IA) — reformulação ampla

| PR | Entrega |
|----|---------|
| #15437 / #15421 | Captain no dropdown de atribuição + atribuição de conversa |
| #15516 | Dashboard de visão geral do assistente redesenhado |
| #15233 / #15315 / #15316 | Modelo de conversation outcome, grão de episódio, gravação por eventos de ciclo de vida |
| #15425 / #15481 | Builders e estatísticas de outcome |
| #15299 / #15303 / #15306 | Política de auto-resolve movida para assistants, timer e política de inatividade |
| #14978 / #14979 / #15017 | Sinais de FAQ agrupados, API e interface de revisão de sugestões |
| #15571 | Toggles de cenário e ferramentas |
| #14902 | Controles de audiência e agendamento para assistants |
| #15140 | Uso de documentos em conversas |
| #15078 | Caminho de geração do Captain visível nas mensagens |
| #15652 | Setup de teste do playground melhorado |
| #15212 | Aceitação de payloads futuros de resposta |
| #15532 | Raciocínio gerado antes das respostas |
| #15317 | Roteamento de conversation completion por feature |
| #15460 | **Overrides de modelo por feature interna** |

> **Relevância para o Chatwit:** crítica. O PR **#15460** e o **#15317** tocam `lib/llm/feature_router.rb`,
> exatamente onde o fork implementa a rota `CAPTAIN_LLM_ROUTE=witdev` (proxy LiteLLM + catálogo
> canônico `platform-api /api/v1/llm/models`). Conflito garantido nesse arquivo — a resolução deve
> preservar a rota witdev **e** absorver o mecanismo de override do upstream.

### 2.5 Campanhas WhatsApp com analytics

| PR | Entrega |
|----|---------|
| #15276 | Rastreamento de analytics de entrega de campanha WhatsApp |
| #15369 | UI de analytics de campanha WhatsApp |

Nova tabela `campaign_recipients` (migration `20260807133000`).

> **Relevância:** alta. A plataforma dispara campanhas em massa via Agent Bot API pelo Chatwit.
> Métricas de entrega nativas reduzem a necessidade de instrumentação própria.

### 2.6 Voz (Voice / Twilio)

| PR | Entrega |
|----|---------|
| #14954 | Dashboard de chamadas de voz |
| #15621 | Gravação e transcrição de chamada por inbox |
| #15241 | Transcrição de gravações de chamada Twilio |
| #15512 | Remux de gravações para ogg (arquivos com duração) |
| #15011 | Webhook de mensagens para inboxes de voz + aba de saúde de webhook |
| #15178 / #15766 | Erro real da Meta / erros de backend em falha de chamada |
| #15014 | Ligar para contato sem conversa existente |

### 2.7 Automação e macros

| PR | Entrega |
|----|---------|
| #15022 | **Automação baseada em tempo** (time based automation) |
| #15472 | Condições em automações com atraso |
| #15416 | Macros executáveis do editor de resposta com `#` |
| #15422 | Macros executáveis da command bar |
| #15447 | Ícones nos dropdowns de macro e automação |
| #15373 | Ação de enviar transcript por email para o email do contato |
| #15113 | Bloqueio de envios inválidos fora da janela de resposta do WhatsApp |

Novas tabelas/colunas: `automation_rule_pending_executions`, `execution_delay` em `automation_rules`,
`status_changed_at` em `conversations`.

### 2.8 Segurança

| PR | Entrega |
|----|---------|
| #15480 | Verificação de assinatura dos webhooks do Slack |
| #15466 / #15463 | Mídia de SMS via safe fetcher e credenciais restritas ao host do provider |
| #15525 | Labels de identidade renderizados como texto puro (XSS) |
| #15521 | Lookup de `source_id` de conversa restrito à conta atual |
| #15207 | Filtragem de acesso a inbox mantida no escopo de participação |
| #15208 / #15209 | Gate de APIs de custom roles e SLA por feature |
| #15379 | Sessões MFA persistidas entre reinícios do navegador |
| #15395 | Hardening de usuário multi-conta no SAML |
| #14103 | Banner de aviso quando os backup codes estão acabando |

> **Relevância:** obrigatória. #15521 e #15207 corrigem vazamento entre contas — o Chatwit é
> multi-tenant em produção.

### 2.9 Performance

| PR | Entrega |
|----|---------|
| #15360 | Índice composto para ordenação de `created_at` de conversa por conta |
| #15264 | Planner fora do scan de inbox mal estimado em queries de label |
| #15321 | Menos trabalho por request no endpoint de filtro de conversas |
| #15570 | Sem queries por membership no payload de auth |
| #15572 | Inserts de audit de sign-in/out em lote |
| #15122 | Reuso da contagem de resolvidos para taxa de reabertura |
| #15412 | `MemoryMax` do sidekiq escalando com a memória do host |
| #15461 | Métricas de fila do Sidekiq no CloudWatch para autoscaling |
| #15381 | Redução do bundle do `sdk.js` |

> **Relevância:** direta. O servidor de produção roda Docker Swarm com sidekiq dedicado;
> #15412 e #15461 afetam o dimensionamento.

### 2.10 Audit log

| PR | Entrega |
|----|---------|
| #15479 | Filtragem, busca e ordenação de audit log |
| #15455 | Mascaramento de IP + geolocalização atrás de flag |
| #15456 | Auditoria de deleção de mensagem com conteúdo original |

### 2.11 Outros

| PR | Entrega |
|----|---------|
| #15261 | Migração do Freshdesk (data imports 1/3) |
| #15346 | Data imports para planos pagos |
| #15050 | Retry de imports Intercom travados após 15 min |
| #15605 | Modo "alerts only" para a integração Slack |
| #15756 | Infraestrutura de billing gated para Shopify |
| #15637 | Inbox access request do TikTok |
| #15629 / #15527 / #15528 | Nomes e identificadores de provider social persistidos e exibidos |
| #15715 | Rotação do token HMAC da inbox |
| #15401 | Cache de canned responses no navegador |
| #15375 / #15348 | Busca e preview nos pickers de menção/variável/emoji e nos dropdowns de filtro |
| #15119 | Merge opt-in de atributos customizados |
| #15124 | Analytics providers no help center |
| #15164 / #15593 / #15640 | Vídeo, upload e preview de mídia no editor de artigos |
| #14870 / #14875 / #14876 | Status em atribuição de agent bot, owner do bot conectado, UI de takeover |
| #15188 | Componente genérico de side drawer |
| #15458 | Charts de relatórios migrados para `@chatwoot/viz` |
| #15001 | Lógica de template WhatsApp/Twilio compartilhada via `@chatwoot/utils` |
| #15153 / #15158 | Metadados de suspensão de conta e acesso a billing suspenso |

---

## 3. Migrations novas (24)

Schema: `2026_07_17_000100` → `2026_08_31_000000`

```
20260709060000_add_execution_delay_to_automation_rules
20260709060100_add_status_changed_at_to_conversations
20260709060200_create_automation_rule_pending_executions
20260714123000_purge_pending_captain_assistant_responses
20260715000000_add_completed_at_to_applied_slas
20260718000000_add_phone_number_health_to_channel_whatsapp
20260724000100_add_index_to_conversations_created_at
20260728000001_add_business_management_token_to_channel_whatsapp
20260729051500_add_status_updated_at_index_to_automation_rule_pending_executions
20260731140853_create_conversation_outcomes
20260803000000_enqueue_copy_captain_auto_resolve_mode_to_assistants_job
20260803130000_add_episode_grain_to_conversation_outcomes
20260804000000_add_cited_document_ids_to_agent_sessions
20260804000001_add_index_on_agent_sessions_cited_document_ids
20260804000002_add_used_faq_ids_to_agent_sessions
20260804000003_add_index_on_agent_sessions_used_faq_ids
20260806000000_add_index_on_agent_sessions_document_ids
20260807101420_add_account_status_created_at_index_to_conversations
20260807133000_create_campaign_recipients
20260811000000_add_ai_assignee_type_to_conversations
20260811000001_backfill_missing_ai_assignee_types
20260813000000_add_geo_location_to_audits
20260814000000_add_associated_created_at_index_to_audits
20260831000000_add_provider_name_to_social_channels
```

> Após o merge: `bundle exec rails db:migrate` obrigatório. Há dois backfills
> (`backfill_missing_ai_assignee_types`, `purge_pending_captain_assistant_responses`) e um
> enqueue de job (`copy_captain_auto_resolve_mode_to_assistants`) — rodar com o Sidekiq ativo.

---

## 4. Matriz de risco de conflito

134 arquivos foram alterados pelos dois lados. Os que importam:

| Arquivo | Nosso delta | Delta upstream | Risco | Estratégia |
|---------|-------------|----------------|-------|-----------|
| `app/services/whatsapp/incoming_message_base_service.rb` | +58/-2 | +46/-49 | **ALTO** | Merge manual. Preservar `extract_interactive_data` e o `content_attrs.merge(...)` em `create_message`. Upstream refatorou o pipeline de identidade (BSUID). |
| `lib/llm/feature_router.rb` | +26/-1 | +23/-5 | **ALTO** | Merge manual. Preservar rota `witdev`; absorver overrides de modelo por feature (#15460) e roteamento por feature (#15317). |
| `config/routes.rb` | +49/-3 | +37/-3 | **MÉDIO** | Aditivo. Preservar rotas Chatwit (`whatsapp_templates`, `evolution_go`, `register_webhook`, `reset_secret`) + novas do upstream. |
| `db/schema.rb` | — | — | **MÉDIO** | Usar versão upstream (maior) + colunas de ambos os lados. |
| `app/services/whatsapp/providers/whatsapp_cloud_service.rb` | +258/-7 | +18/-14 | **MÉDIO** | Preservar `send_template_from_payload`, branch `content_type: 'template'`. |
| `app/javascript/dashboard/components-next/message/Message.vue` | +313/-8 | +24/-2 | **MÉDIO** | Blocos `if` separados; preservar roteamento para `WhatsAppInteractive.vue` e `RichCards.vue`. |
| `enterprise/app/models/enterprise/message.rb` | +1/-1 | +24/-0 | **MÉDIO** | Predominantemente upstream (Captain generation path); conferir. |
| `app/javascript/dashboard/routes/dashboard/Dashboard.vue` | +55/-40 | +6/-7 | **MÉDIO** | Preservar `<MobileLayout v-if="isSmallScreen" />` do PWA. |
| `config/integration/apps.yml` | +77/-0 | +10/-1 | **BAIXO** | Aditivo — manter Socialwise + JusMonitorIA + novas integrações. |
| `lib/redis/redis_keys.rb` | +12/-0 | +1/-0 | **BAIXO** | Aditivo — manter chaves de debounce. |
| `app/models/message.rb` / `inbox.rb` | +12/-1 · +6/-1 | +3/-0 · +1/-5 | **BAIXO** | Aditivo. |
| `config/locales/en.yml`, `pt_BR.yml`, i18n JSON | — | — | **BAIXO** | Aditivo — manter chaves de ambos. |
| `public/brand-assets/*` | — | — | **ZERO** | Sempre Chatwit (`--ours`). |
| `chatwitdocs/` | — | — | **ZERO** | Sempre nosso (`--ours`). |

Arquivos protegidos **sem** alteração upstream (risco zero, conflito impossível):
`webhook_listener.rb`, `instagram/base_message_builder.rb`, `facebook/message_builder.rb`,
`lib/integrations/socialwise*/`, `lib/integrations/jusmonitoria/`, `config/initializers/00_chatwit.rb`,
`components-next/mobile/`.

---

## 5. Enterprise

O overlay `enterprise/` tem 15 arquivos em sobreposição, concentrados em Captain
(`captain_listener.rb`, `conversation_completion_service.rb`, `agentable.rb`,
`inbox_pending_conversations_resolution_job.rb`) e em
`enterprise/app/services/messages/audio_transcription_service.rb`.

Regra de resolução: o Enterprise é overlay do upstream — prevalece o upstream, **exceto** onde o
fork injetou a rota witdev de LLM. Ponto de atenção: `audio_transcription` e `help_center_search`
permanecem na rota legada do Chatwoot (decisão registrada no sync v4.16.0); confirmar que
segue assim após o merge.

---

## 6. Plano de execução

1. Commit das mudanças locais pendentes (`.dockerignore`, docs do fork) — preservar trabalho do usuário
2. Backup: `git branch backup/pre-upstream-sync-20260912`
3. `git merge upstream/develop`
4. Resolução individual de cada conflito conforme a matriz acima
5. Verificação: sem marcadores de conflito, customizações protegidas presentes, `HEAD..upstream/develop == 0`
6. Lint focado nos arquivos tocados (`rubocop`, `eslint`)
7. Commit do merge, push em `origin/develop`
8. Atualização de `AGENTS.md` / `CLAUDE.md` com o histórico de migração
9. Perguntar ao usuário sobre deploy via `./build.sh`

## 7. Pós-merge (checklist operacional)

- [ ] `bundle install` (Gemfile.lock alterado pelo upstream)
- [ ] `pnpm install` (package.json alterado — `@chatwoot/viz`, `@chatwoot/utils`)
- [ ] `bundle exec rails db:migrate` (24 migrations, 2 backfills, 1 enqueue de job)
- [ ] Verificar `CAPTAIN_LLM_ROUTE=witdev` ainda ativo após mudanças no `feature_router`
- [ ] Verificar QUICK_REPLY do WhatsApp (`extract_interactive_data`) com mensagem real
- [ ] Verificar renderização de rich messages (WhatsApp interactive + Instagram cards)
- [ ] Verificar PWA mobile (`MobileLayout`) e Web Push
- [ ] Verificar auto-provisioning do Chatwit Platform Bot no startup
