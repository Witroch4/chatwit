#Chatwit
SERVIDOR DE PRODUÇÃO ssh -i ~/.ssh/keys/production-server.key root@49.13.155.94 "docker exec... docker service principal: chatwoot_app_chatwoot_sidekiq

POSTGRES SHARED INFRA LOCAL docker exec postgres psql -U postgres -lqt

## Mobile Module (PWA) — Fork Exclusivo Chatwit

Chatwit tem um **módulo mobile PWA completo** em `components-next/mobile/`. Regras críticas:
icones reutilizaveis apps/socialwise-frontend/components/icons/index.tsx
1. **ISOLAMENTO TOTAL do desktop.** O módulo mobile é 100% visual — renderiza condicionalmente via `<MobileLayout v-if="isSmallScreen" />` em `Dashboard.vue`. Nenhuma funcionalidade desktop pode ser alterada ou quebrada pelo mobile. Zero regressão.
2. **CONECTAR, não recriar.** Toda feature solicitada para mobile **já existe na versão desktop**. O trabalho é sempre **conectar** stores, composables, APIs e componentes existentes ao layout mobile. Nunca reimplemente lógica que o desktop já tem.
3. **Push via Web Push (VAPID)**, não Firebase/FCM. Chaves auto-geradas. Service worker em `public/sw.js`.
4. **Código:** `components-next/mobile/`, i18n em `locale/*/mobile.json`. Doc: `chatwitdocs/Chatwoot-Chatwit-mobile.md`.

## Infra compartilhada local

- Rede Docker: `minha_rede`
- PostgreSQL compartilhado: host `postgres`, porta `5432`, imagem `pgvector/pgvector:pg17`
- Redis compartilhado: host `redis`, porta `6379`, imagem `redis:8.6.1`
- Compose da infra: `/home/wital/shared-infra/docker-compose.yml`
- Os scripts `dev.sh` devem reutilizar essa infra e subir `postgres`/`redis` apenas se ainda não estiverem ativos

## Regra para Docker Compose

- Não adicionar `version:` no topo de arquivos `docker-compose*.yml`/`docker-compose*.yaml`; esse campo está deprecated no Compose atual

> **Universal Agent Instructions** — Compatible with Claude Code, Cursor, Copilot, Codex, Gemini CLI, and other AI coding agents.

## LLM — fonte única e consulta obrigatória

Antes de criar, alterar, depurar ou operar qualquer fluxo de LLM, leia
`/home/wital/witdev-platform-core/docs/LLM-CANONICAL-FLOW-ALL-APPS.md`.
Este é o único documento normativo para catálogo, seleção e roteamento de modelos nesta máquina.

Regra inegociável (espelha o CLAUDE.md da witdev-platform-core): **`platform-litellm` é a
autoridade máxima de modelos e roteamento; `platform-api /api/v1/llm/models` é o ÚNICO
contrato de listagem de modelos para apps.** O Chatwit NÃO mantém catálogo próprio de
modelos e NÃO chama o LiteLLM `/model/info` ou `/v1/models` diretamente para listagem.

- Todo seletor/dropdown de modelos no Chatwit consome `Chatwit::LlmProxy.catalog_models`
  (`lib/chatwit/llm_proxy.rb`), que consulta `CAPTAIN_WITDEV_CATALOG_URL`
  (default `http://platform-api:8000/api/v1/llm/models`) pela rede interna Docker.
- Persistir/enviar somente o alias canônico (`value`) do catálogo.
- Fallback local só como degradação sinalizada (catálogo central indisponível/vazio);
  se o central responder com qualquer modelo, a lista é 100% central, sem merge.
- Execução (completions) vai ao proxy LiteLLM OpenAI-compatible
  (`CAPTAIN_WITDEV_PROXY_URL`, default `http://platform-litellm:4000` + `/v1`) com
  `CAPTAIN_WITDEV_PROXY_API_KEY`; rota ativada por `CAPTAIN_LLM_ROUTE=witdev`.
- Fonte de verdade: `/home/wital/witdev-platform-core/docs/LLM-CANONICAL-FLOW-ALL-APPS.md`.


## Regras Arquiteturais Criticas (LEITURA OBRIGATORIA)

1. **WITDEV PLATFORM = CÉREBRO | CHATWIT = CARTEIRO E FONTE DE LEADS:** A Witdev Platform Core (`witdev-platform-core`) detém 100% da inteligência, processamento, lógica de fluxo, IA, classificação e monitoramento jurídico. O Chatwit é estritamente o **carteiro** — recebe mensagens dos canais (WhatsApp, Instagram, Facebook), encaminha para a plataforma, e entrega as respostas de volta ao lead. O Chatwit também é a **fonte primária de leads e contatos** da plataforma: todo lead entra pelo Chatwit e é sincronizado com a plataforma via webhook dedicado (Lead Sync). O Chatwit **NUNCA** processa lógica de negócio.
2. **Dois produtos, um carteiro:** O Chatwit serve dois produtos da plataforma simultaneamente:
   - **Socialwise** — automação de atendimento, flows, campanhas em massa, templates WhatsApp
   - **JusMonitorIA** — monitoramento jurídico de processos, notificações proativas a advogados
   Cada produto tem seu próprio bot auto-provisionado, webhook e contrato de integração, mas ambos passam pelo Chatwit como canal de entrega.
3. **Duas vias de comunicação:**
   - **Sync (webhook):** Chatwit envia à plataforma e mantém ponte aberta por até 30s. Resposta volta na mesma request.
   - **Async (Agent Bot API):** Plataforma envia de volta ao Chatwit via bot token (campanhas, respostas que ultrapassam 30s, flows, notificações jurídicas).
4. **Contrato unificado (FONTE DE VERDADE):** O contrato que governa toda a comunicação entre Chatwit e a plataforma está em **`witdev-platform-core/docs/contrato-plataforma-unificada.md`** (caminho local: `/home/wital/witdev-platform-core/docs/contrato-plataforma-unificada.md`). Este documento substitui os contratos legados (`chatwitdocs/chatwit-contrato-async-30s.md` e `chatwitdocs/JusmonitorIA-contrato.md`, ambos deprecados). Leia o contrato unificado ANTES de implementar qualquer integração nova.
5. **NUNCA** modifique código nativo do Chatwoot sem necessidade. **PREFIRA** criar novos arquivos/métodos a modificar existentes. **MANTENHA** compatibilidade com atualizações futuras do Chatwoot.
6. **SEMPRE** documente alterações em `chatwitdocs/`.

SERVIDOR DE PRODUÇÃO ssh -i /home/wital/Chatwit-Social-dev/id_rsa.v3 root@49.13.155.94 "docker service ls"

---

## Dinâmica Witdev Platform <> Chatwit (Contrato Unificado)

A Witdev Platform Core é mantida por uma **equipe separada**. Mudanças na integração são feitas via **contrato documentado**, não por gambiarras.

### Contrato unificado (fonte de verdade)

**`witdev-platform-core/docs/contrato-plataforma-unificada.md`**
(caminho local: `/home/wital/witdev-platform-core/docs/contrato-plataforma-unificada.md`)

Este documento cobre TODOS os contratos de integração:
- **Contrato 1: Socialwise Flow** — webhook de mensagens, botões, flows, dual-mode sync/async
- **Contrato 2: JusMonitorIA** — webhook de eventos (contato, mensagem, tag), monitoramento jurídico
- **Contrato 3: Payment (InfinitePay)** — confirmação de pagamento, auto-create PaymentLink
- **Contrato 4: Lead Sync** — sincronização de leads e arquivos da plataforma
- **API: Plataforma → Chatwit (Agent Bot)** — entregas async, templates, mídia, contatos

> **Deprecados:** `chatwitdocs/chatwit-contrato-async-30s.md` e `chatwitdocs/JusmonitorIA-contrato.md` foram substituídos pelo contrato unificado. Consulte-os apenas como referência histórica.

### Como funciona
1. A plataforma documenta a necessidade no contrato unificado com: contexto, payload, código Ruby proposto, complexidade
2. A equipe Chatwit lê o contrato e implementa
3. Ao implementar, marca como IMPLEMENTADO no changelog do contrato

### Tokens e credenciais
- **Chatwit Platform Bot token** (global, `account_id=NULL`): auto-provisionado no startup em `config/initializers/00_chatwit.rb`, registrado na plataforma via `/init`; substitui os bots legados separados de Socialwise/JusMonitorIA.
- **ENVs:** `SOCIALWISE_WEBHOOK_URL`, `JUSMONITORIA_WEBHOOK_URL`, `CHATWIT_WEBHOOK_SECRET`, `FRONTEND_URL`
- **User token** (`chatwitAccessToken`): apenas para operações específicas do usuário, **nunca** para operações de sistema/campanha.

---

## MIGRACAO: SocialWise Enterprise -> Chatwit 4.10

### Contexto

- **Nome do Produto:** Chatwit 4.10
- **Base:** Chatwoot 4.10.1 (oficial)
- **Customizações:** SocialWise Enterprise (fork v4.4)
- **Objetivo:** Unificar as customizações SocialWise no Chatwoot mais recente

### Status das Etapas

| Etapa | Descrição | Status | Documentação |
|-------|-----------|--------|--------------|
| 1 | SocialWise Flow (debounce, webhook, mensagens ricas) | Completa | `chatwitdocs/migration-etapa1.md` |
| 2 | Rich Messages Rendering (WhatsApp/Instagram templates, botões, imagens) | Completa | `chatwitdocs/migration-etapa2.md` |
| 3 | Stickers (rotas, frontend, upload) | Completa | `chatwitdocs/migration-etapa3-stickers.md` |
| 4 | UI/UX customizações | Pendente | - |

### Arquivos criticos de referencia

| Arquivo | O que é | Quando usar |
|---------|---------|-------------|
| `codigo_das_minhas_mudancas.diff` | Diff completo do fork Witdev 4.4 | Entender o que foi modificado |
| `chatwitdocs/migration-etapa1.md` | Doc da Etapa 1 (SocialWise Flow) | Arquivos, config, fluxo |
| `chatwitdocs/chatwit-contrato-async-30s.md` | Contrato de integração Socialwise | Novas features de integração |
| `fork-witdev-4.4-modificacoes/` | Arquivos originais do fork v4.4 | Copiar arquivos não migrados |

### Componentes SocialWise no Chatwit

```
lib/integrations/
├── socialwise/                         # Core SocialWise
│   ├── cache_manager.rb               # Gerenciador de cache
│   ├── instagram_response_processor.rb # Processador Instagram
│   └── webhook_enhancer_service.rb    # Enriquecedor de webhook
└── socialwise_flow/                    # Motor de Fluxo
    ├── processor_service.rb           # Serviço principal
    ├── debounce_processor_service.rb  # Processador de debounce
    └── whatsapp_response_processor.rb # Processador WhatsApp

config/initializers/
├── 00_chatwit.rb                      # Auto-provisioning do Chatwit Platform Bot + migração dos bots legados
└── socialwise_cache.rb                # Preload de cache

app/jobs/socialwise_*.rb               # Jobs (debounce, etc.)
app/controllers/api/v1/accounts/integrations/socialwise_*.rb  # Controllers
```

### Variáveis de Ambiente SocialWise

| Variável | Descrição | Padrão |
|----------|-----------|--------|
| `SOCIALWISE_DEBOUNCE_MS` | Tempo de debounce em ms | `0` (desabilitado) |
| `SOCIALWISE_DEBOUNCE_MAX_MS` | Timeout máximo do debounce | `30000` |
| `SKIP_SOCIALWISE_CACHE` | Desabilita preload de cache | `false` |
| `SOCIALWISE_WEBHOOK_URL` | URL base do Socialwise | - |
| `CHATWIT_WEBHOOK_SECRET` | Secret compartilhado com Socialwise | - |
| `FRONTEND_URL` | Base URL do Chatwit | `https://chatwit.witdev.com.br` |
| `SOCIALWISE_FLOW_TIMEOUT` | Timeout sync em segundos | `30` |

---

## Build / Test / Lint

- **Setup**: `bundle install && pnpm install`
- **Run Dev**: `pnpm dev` or `overmind start -f Procfile.dev`
- **Seed Local Test Data**: `bundle exec rails db:seed` (quickly populates minimal data for standard feature verification)
- **Seed Search Test Data**: `bundle exec rails search:setup_test_data` (bulk fixture generation for search/performance/manual load scenarios)
- **Seed Account Sample Data (richer test data)**: `Seeders::AccountSeeder` is available as an internal utility and is exposed through Super Admin `Accounts#seed`, but can be used directly in dev workflows too:
  - UI path: Super Admin → Accounts → Seed (enqueues `Internal::SeedAccountJob`).
  - CLI path: `bundle exec rails runner "Internal::SeedAccountJob.perform_now(Account.find(<id>))"` (or call `Seeders::AccountSeeder.new(account: Account.find(<id>)).perform!` directly).
- **Lint JS/Vue**: `pnpm eslint` / `pnpm eslint:fix`
- **Lint Ruby**: `bundle exec rubocop -a`
- **Test JS**: `pnpm test` or `pnpm test:watch`
- **Ruby Version**: Manage Ruby via `rbenv` (`eval "$(rbenv init -)"` antes de `bundle`/`rspec`)
- **rbenv setup**: Before running any `bundle` or `rspec` commands, init rbenv in your shell (`eval "$(rbenv init -)"`) so the correct Ruby/Bundler versions are used
- Always prefer `bundle exec` for Ruby CLI tasks (rspec, rake, rubocop, etc.)
- **Test env**: Specs should run without `.env`. If present, temporarily rename it (e.g., `.env` -> `.env.bak`) while running specs and restore afterward.
- **Validação após mudanças (obrigatória)**: depois de qualquer modificação, rode pelo menos a validação mais específica do stack alterado antes de concluir o trabalho. Prefira checks focados nos arquivos tocados (`pnpm eslint path/to/file.vue`, `bundle exec rubocop path/to/file.rb`, `bundle exec rspec spec/path/to/file_spec.rb`) e só escale para suites maiores quando necessário.
- **Host validation**: com `pnpm install` e `bundle install` já feitos, `eslint`, `vitest`, `rubocop` e `rspec` podem rodar no host. Para Ruby/test use `rbenv`, rode sem `.env` e aponte para a infra Docker compartilhada publicada no host (`POSTGRES_HOST=127.0.0.1`, `POSTGRES_PORT=5432`, `POSTGRES_USERNAME=postgres`, `POSTGRES_PASSWORD=postgres`; Redis em `redis://127.0.0.1:6379/0` quando necessário).

### Testes Ruby (preferir Docker, host permitido com infra compartilhada)

Os testes Ruby continuam **preferencialmente** no container Docker para manter o fluxo do time consistente. Porém, neste ambiente, o host também pode rodar `rspec`/`rails` em `RAILS_ENV=test` usando o PostgreSQL/Redis publicados pela infra compartilhada em `127.0.0.1`.

```bash
docker ps                                    # Verificar containers
./dev.sh start                               # Iniciar se necessário
./dev.sh shell                               # Shell no container Rails
bundle exec rspec spec/path/to/file_spec.rb  # Rodar testes
bundle exec rspec spec/path/to/file_spec.rb:LINE_NUMBER  # Teste individual
```

> Se rodar no host, use `rbenv`, remova `.env` temporariamente e aponte o banco para `127.0.0.1:5432` com `POSTGRES_USERNAME=postgres` e `POSTGRES_PASSWORD=postgres`. Se aparecer `PG::ConnectionBad`, verifique se os containers `postgres`/`redis` estão ativos e se o banco de teste já foi preparado.

## Code Style

- **Ruby**: RuboCop (150 char max line)
- **Vue/JS**: ESLint (Airbnb base + Vue 3 recommended)
- **Vue Components**: PascalCase, Composition API com `<script setup>`
- **Events**: camelCase
- **I18n**: No bare strings; use i18n (`en.yml` backend, `en.json` frontend)
- **Error Handling**: Custom exceptions (`lib/custom_exceptions/`)
- **Models**: Validate presence/uniqueness, add proper indexes
- **Type Safety**: PropTypes in Vue, strong params in Rails

## Styling

- **Tailwind Only**: No custom CSS, no scoped CSS, no inline styles
- **Colors**: Refer to `tailwind.config.js`

## General Guidelines

- MVP focus: Least code change, happy-path only
- Ship the happy path first; iterate after confirmation
- Prefer the smallest production-ready change that solves the current problem.
- Build for the expected production path first. Do not add speculative guards, fallbacks, retries, or edge-case handling unless the caller can actually hit that case or production has proven it necessary.
- Enforce eligibility and exclusivity rules at the earliest shared entry point. Do not repeat backup guards across downstream jobs, callbacks, services, or writes unless a proven independent path bypasses that point.
- Validate request parameters at the controller or request boundary, reusing existing errors so invalid input returns `422 Unprocessable Entity` instead of reaching models or Sentry.
- Accept only the documented type, shape, and value. Do not add compatibility coercions for malformed client values; fix official clients instead.
- When an impossible or misconfigured state would indicate a setup/deployment bug, let it fail loudly instead of silently skipping behavior.
- For locked/internal configs that must exist in production, prefer direct reads (`find`, `find_by!`, required hash keys) over silent fallbacks.
- Do not add validation or response checks unless the code uses the result or the check changes behavior meaningfully.
- Prefer existing repo dependencies/client libraries over hand-rolled protocol code for auth, signing, parsing, or API plumbing.
- Avoid one-use private helpers unless they hide real complexity or make the main flow meaningfully easier to read.
- Prefer minimal, readable code over elaborate abstractions; clarity beats cleverness
- Break down complex tasks into small, testable units
- Iterate after confirmation
- In specs, avoid custom helper methods for setup/data. Prefer `let` values and direct per-example setup; only add a helper when it removes meaningful repeated complexity.
- Remove dead/unreachable/unused code
- Don't write multiple versions — pick the best approach
- Avoid writing specs unless explicitly asked
- Prefer `with_modified_env` over stubbing `ENV` in specs
- Specs in parallel: prefer `error.class.name` over constant equality

## Codex Worktree Workflow

- Use a separate git worktree + branch per task to keep changes isolated.
- Keep Codex-specific local setup under `.codex/` and use `Procfile.worktree` for worktree process orchestration.
- The setup workflow in `.codex/environments/environment.toml` should dynamically generate per-worktree DB/port values (Rails, Vite, Redis DB index) to avoid collisions.
- Start each worktree with its own Overmind socket/title so multiple instances can run at the same time.

## Fluxo canônico de entrega (OBRIGATÓRIO)

- **SEMPRE mesclar localmente de volta em `develop`, criar COMMIT convencional e executar PUSH com `git push origin develop`.**
- Ao concluir qualquer tarefa no Chatwit, não oferecer opções de integração nem deixar a entrega apenas em branch/worktree.
- Preservar integralmente as mudanças locais existentes durante a mesclagem; nunca descartar trabalho do usuário.
- Depois do push, perguntar APENAS se deve fazer deploy com build em produção via `./build.sh`.
- Nunca executar `./build.sh` sem autorização explícita do usuário. Quando autorizado, acompanhar build, push das imagens e rollout dos serviços até o resultado final.

## Commit Messages

- Conventional Commits: `type(scope): subject`
- Example: `feat(socialwise): add template dispatch via agent bot`
- Example: `fix(instagram): correct rich message mapping`
- **Migração:** `migration(etapaN): description`
- Don't reference Claude in commit messages

## PR Description Format

- Start with a short, user-facing paragraph describing the product change.
- Add a `Closes` section with relevant issue links (GitHub, Linear, etc.).
- For feature PRs, add `How to test` from a product/UX standpoint.
- For bugfix PRs, use `How to reproduce` when helpful.
- Optionally add a `What changed` section for implementation highlights.
- Do not add a `How this was tested` section listing specs/commands.

## Project-Specific

- **Translations**:
  - For product and source-string changes, only update `en.yml` and `en.json`; other languages are handled through Crowdin and the community
  - Crowdin-generated translation sync PRs may update non-English locale files; do not flag those changes solely for modifying translated locale files
  - Preserve product and brand names, OAuth scopes, API values, and other machine-readable identifiers unless an official localized form exists
  - When reviewing Crowdin syncs, verify protected terms remain unchanged. Add newly introduced product names, brand names, and machine-readable identifiers to the Crowdin glossary as non-translatable, and keep the glossary current
  - Backend i18n → `en.yml`, Frontend i18n → `en.json`
- **Frontend**:
  - Use `components-next/` for message bubbles (the rest is being deprecated)

## Ruby Best Practices

- Use compact `module/class` definitions; avoid nested styles

## Frontend Conventions

- Prefer existing design-system utilities and shared composables.
- Use typography utilities instead of manually recreating font styles.
- Use logical Tailwind utilities (`ms`, `me`, `start`, `end`) for direction-aware layouts.
- Use `rem` for arbitrary CSS dimensions; preserve native numeric values required by chart/SVG APIs.
- Extract repeated or domain-specific strings, thresholds, colors, and durations into named constants.
- Use shared request-cancellation utilities instead of local `AbortController` logic.

## Enterprise Edition Notes

- Enterprise overlay under `enterprise/` extends/overrides OSS code
- Search both trees before editing (`rg -n "FooService" app enterprise`)
- New endpoints/services: consider Enterprise override or extension point (`prepend_mod_with`)
- Keep request/response contracts stable across OSS and Enterprise
- Enterprise-specific specs under `spec/enterprise`
- For Enterprise-only behavior: add Enterprise module instead of editing OSS directly

Practical checklist for any change impacting core logic or public APIs
- Search for related files in both trees before editing (e.g., `rg -n "FooService|ControllerName|ModelName" app enterprise`).
- If adding new endpoints, services, or models, consider whether Enterprise needs:
  - An override (e.g., `enterprise/app/...`), or
  - An extension point (e.g., `prepend_mod_with`, hooks, configuration) to avoid hard forks.
- Avoid hardcoding instance- or plan-specific behavior in OSS; prefer configuration, feature flags, or extension points consumed by Enterprise.
- Keep request/response contracts stable across OSS and Enterprise; update both sets of routes/controllers when introducing new APIs.
- When renaming/moving shared code, mirror the change in `enterprise/` to prevent drift.
- Tests: Add Enterprise-specific specs under `spec/enterprise`, mirroring OSS spec layout where applicable.
- When modifying existing OSS features for Enterprise-only behavior, add an Enterprise module (via `prepend_mod_with`/`include_mod_with`) instead of editing OSS files directly—especially for policies, controllers, and services. For Enterprise-exclusive features, place code directly under `enterprise/`.

## Branding / White-labeling note

- For user-facing strings that currently contain "Chatwoot" but should adapt to branded/self-hosted installs, prefer applying `replaceInstallationName` from `shared/composables/useBranding` in the UI layer (for example tooltip and suggestion labels) instead of adding hardcoded brand-specific copy.

---

## Historico de Migração

### 2026-07-18 - Upstream sync v4.16.0 (405 commits)
- Sync type: Normal merge
- Upstream commit: `a752e56765a46bb62571932fe6bebf0b71b31b61`
- Conflicts: 76 resolved, including 28 binary branding assets preserved from Chatwit
- Critical: all 10 generative features from `config/llm.yml` use the canonical WitDev catalog and proxy when `CAPTAIN_LLM_ROUTE=witdev`; `audio_transcription` and `help_center_search` remain on the legacy Chatwoot route. SocialWise, JusMonitorIA, Payment Phase 2, Evolution Go, rich messages, mobile PWA and Web Push were preserved.
- Documentation: `chatwitdocs/upstream-sync-v4.16.0.md`

### 2026-04-20 - Upstream sync v4.13.0 (160 commits)
- Sync type: Normal merge
- New merge-base: `437dd9d3`
- Conflicts: 13 resolved
- Critical: provisioning dos bots agora é centralizado em `config/initializers/00_chatwit.rb`; `socialwise_bot.rb`/`jusmonitoria_bot.rb` são legados. O upstream removeu `lib/tasks/auto_annotate_models.rake` em favor de `lib/tasks/annotate_rb.rake`, e `config/routes.rb` agora precisa preservar `register_webhook`/`reset_secret` junto das rotas Chatwit (`whatsapp_templates` e `evolution_go`).

### 2026-02-22 - Seções 13-15: Template Dispatch, Contacts API, Bot Init
- Branch `content_type: 'template'` + `send_template_from_payload()` no `whatsapp_cloud_service.rb`
- `contacts` (search, create, show) adicionado ao `BOT_ACCESSIBLE_ENDPOINTS`
- Init do Agent Bot no Socialwise via `POST /init` no startup
- **Contrato:** `chatwitdocs/chatwit-contrato-async-30s.md` seções 13, 14, 15

### 2026-02-01 - Etapa 2: Rich Messages Rendering
- Renderização visual de templates WhatsApp com imagem e botões
- Renderização de cards Instagram/Facebook (carrosséis, quick replies)
- Componentes Vue: `WhatsAppInteractive.vue`, `RichCards.vue`
- Service mapper: `WhatsappRendererMapper.rb`

### 2026-01-30 - Etapa 1: SocialWise Flow
- Integração do motor de fluxo com debounce para envio ao webhook SocialWise
- Suporte a WhatsApp, Instagram e Facebook
- Processamento de respostas do SocialWise (mensagens interativas, templates)
- hook_type: inbox para conectar à caixa de entrada

---

## Referencia Rapida de Comandos

```bash
# Desenvolvimento
overmind start -f Procfile.dev

# Após modificações
bundle install
bundle exec rails db:migrate

# Lint
bundle exec rubocop -a
pnpm eslint:fix

# Verificar contrato Socialwise
cat chatwitdocs/chatwit-contrato-async-30s.md
```
