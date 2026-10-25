# Upstream sync Chatwoot 4.19.1

Data: 2026-10-25

## Escopo

O Chatwit saiu da base Chatwoot 4.17.1 para `upstream/develop` no release 4.19.1
(`3564ec1e96`) por meio de um merge Git real (sem cherry-pick). Foram 214 commits e
206 PRs upstream, nenhum deles já presente no fork. O merge-base saudável anterior
(`2f1ed80f89`) foi confirmado antes do merge. Backup pré-sync:
`backup/pre-upstream-sync-20261025`.

41 conflitos resolvidos arquivo a arquivo (40 de conteúdo + 1 modify/delete), sem
resolução em massa para um dos lados.

## Dependências

- `ruby_llm ~> 2.0.0` e `ai-agents ~> 0.13.0`; `ruby_llm-schema` saiu do Gemfile e o
  Chatwit não o usa. `rubyzip ~> 2.3` (dossiê) e `httparty` foram preservados.
- Upstream removeu `time_diff` e `spring`; nenhum código Chatwit os usava.

## Pontos críticos para os próximos syncs

### RubyLLM 2.0 quebrou o registro de aliases do proxy WitDev

`RubyLLM.models.all` agora devolve uma cópia filtrada e `RubyLLM::Model::Info` virou
`RubyLLM::Model`. Em `lib/chatwit/llm_proxy.rb`, `register_model!` passou a usar
`RubyLLM.models.all_including_unlisted` (o array vivo) e `RubyLLM::Model.default`.
Sem isso nenhum alias do catálogo central seria registrado e toda chamada na rota
`CAPTAIN_LLM_ROUTE=witdev` falharia com `Unknown model`.

`Llm::Models.temperature_for` (novo no upstream) consulta o registro do RubyLLM; em
produção o alias já foi registrado por `Chatwit::LlmProxy.resolve_model!` antes disso.

### A rota WitDev continua em chat completions

O upstream passou a usar a Responses API da OpenAI sempre que `CAPTAIN_OPEN_AI_ENDPOINT`
está vazio (`Captain::ResponsesConfig`). O proxy LiteLLM do Chatwit é OpenAI-compatible
em chat completions, então:

- `Llm::FeatureRouter.standard_openai_endpoint?` retorna `false` quando
  `Chatwit::LlmProxy.route_witdev?`;
- `Chatwit::AiAgentsConfiguration.configure_witdev` fixa
  `openai_protocol = :chat_completions`;
- `Llm::Config#configure_openai` na rota legada acrescenta `/v1` ao endpoint
  (comportamento novo do RubyLLM 2.0).

`config/initializers/ai_agents.rb` mantém os dois ramos (WitDev e legado com
`CAPTAIN_GEMINI_API_KEY`) e adota `model_registry_file` do upstream no ramo legado.

### Exclusividade de provedor de bot (novo no upstream)

Upstream passou a impedir Agent Bot, Dialogflow e Captain no mesmo inbox
(`Inbox#conflicting_bot_provider`). O Captain **phase2_only** do Chatwit coexiste com o
Agent Bot do Socialwise, então a regra só vale para o modo `continuous`:

- `CaptainInbox`: `validate :ensure_exclusive_bot_provider, if: :continuous?`
- `Enterprise::Inbox#conflicting_bot_provider` consulta `CaptainInbox.continuous`.

Este é o 4º ponto de guarda de `phase2_only?` (os outros três continuam:
`InboxPendingConversationsResolutionJob`, `ConversationsResolutionSchedulerJob` e
`HookExecutionService#captain_assistant_configured?`). Verificar os quatro a cada sync.

### `captain_integration_v2` está deprecated

O gate do assistente passou a ser `captain_integration` (`Agentable#agent_model`,
`Llm::BaseAiService#captain_assistant?`, antes `captain_v2_assistant?`). A short-circuit
da rota WitDev continua antes do gate.

### Super Admin redesenhado

As telas do Super Admin foram reescritas com parciais novos (`standalone`, `section`,
`alert`, `button` ...). Reaplicado sobre a versão upstream:

- branding Chatwit em `_standalone` (título/logos) e `_brand`; heading do onboarding em
  `config/locales/en.yml`;
- `_javascript.html.erb` mantém o widget de suporte Chatwoot **desativado** (privacidade) e
  o botão "Chat Support" de `settings/show` foi removido; e-mail de contato
  `suporte@witdev.com.br`;
- `app_configs/show`: aviso `@chatwit_witdev_warning` e selects `fail-closed`
  (`type: select` sem opções não vira campo de texto);
- `accounts/show`: toggle "Captain Payment Phase 2" no tab Maintenance, no novo estilo.

### Outros

- `Message.vue`: mantidos menu de contexto mobile (long-press), seleção de dossiê, e
  juntados `ForwardEmailPanel`, tradução automática e `isForwardedEmail` do upstream.
- `MessagesView.vue`: label suggestions e o botão de quoted reply foram removidos pelo
  upstream (e `LabelSuggestion` + spec); mantidos `DossierBar` e `overflow-x-hidden`.
- `SendReplyJob`: tradução pendente do upstream roda antes do roteamento
  `send_meta_rich_message` do Socialwise.
- `Channel::FacebookPage#subscribe`: campos `messaging_postbacks` (upstream) e `feed`
  (Socialwise) juntos.
- `config/schedule.yml`: `whatsapp_stuck_message_recovery_job` e
  `trigger_conversations_resolution_job` (agora com `AUTO_RESOLVE_CRON`).
- Specs: stubs do WhatsApp Cloud mantidos em `v22.0`; novos specs de config do Super Admin
  stubam `Chatwit::LlmProxy.operational_models`.

## Validação

- `rubocop` nos arquivos Ruby tocados, `eslint` nos Vue/JS tocados, `bundle install` e
  `pnpm install --frozen-lockfile` sem erros, schema carregado no banco de teste.
- Specs de LLM/Captain/config/schedule, controllers do Super Admin e jobs/serviços
  relacionados passam.
- `spec/enterprise/models/message_spec.rb` (4 exemplos de
  `mark_pending_conversation_as_open_for_human_response`) já falha no backup pré-sync;
  não é regressão deste merge.
