# Chatwit Upstream 4.16 Enterprise Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Merge Chatwoot upstream 4.16 into Chatwit while preserving every fork-only feature and proving the Enterprise Captain stack before production rollout.

**Architecture:** A real merge of `upstream/develop` preserves history and advances the merge-base. Upstream's new `Llm::FeatureRouter` remains authoritative for legacy Chatwoot routing, while the WitDev route delegates its four generative features to the central catalog through `Chatwit::CaptainModelResolver`. Conflict resolution is grouped by domain, but no merge commit is created until all groups are internally consistent.

**Tech Stack:** Git, Ruby 3.4.4, Rails 7.1, Enterprise overlay, RSpec, Vue 3, Vitest, ESLint, pnpm, PostgreSQL 17, Redis 8, Docker Swarm, Portainer.

## Global Constraints

- Use `git merge`; never bulk cherry-pick, rebase, squash, or strategy-resolve all conflicts to one side.
- Keep `CAPTAIN_LLM_ROUTE=chatwoot` behavior compatible with upstream 4.16.
- Route WitDev model listing only through `platform-api /api/v1/llm/models` and execution only through `platform-litellm`.
- A WitDev catalog without top-level `source == "litellm_proxy"` is not operational and cannot authorize persistence or execution.
- Keep embeddings, OpenAI Files API, and native Whisper on their legacy paths.
- Preserve `extract_interactive_data`, SocialWise, JusMonitorIA, Evolution Go, rich messages, mobile PWA, Web Push/VAPID, and Chatwit branding.
- Treat every Enterprise failure as a merge regression until its cause is proven otherwise.
- Do not add `version:` to Docker Compose files.
- Keep the user's dirty `/home/wital/chatwit` checkout untouched; work only in `.worktrees/upstream-v4.16.0-20260718` until final local integration.

---

### Task 1: Perform the historical merge and freeze the conflict inventory

**Files:**
- Modify: Git index and all files changed by `upstream/develop`
- Reference: `docs/superpowers/specs/2026-07-18-chatwit-upstream-v4-16-enterprise-design.md`

**Interfaces:**
- Consumes: `upstream/develop` at `a752e56765a46bb62571932fe6bebf0b71b31b61`
- Produces: an in-progress merge with a fixed list of unresolved paths

- [ ] **Step 1: Verify branch, backup, upstream head, and clean worktree**

Run:

```bash
git status --short --branch
git rev-parse backup/pre-upstream-sync-20260718
git rev-parse upstream/develop
```

Expected: branch `sync/upstream-v4.16.0-20260718`, backup at `6b868b58e...`, upstream at `a752e56765...`, no uncommitted files.

- [ ] **Step 2: Merge upstream with a real merge commit pending**

Run:

```bash
git merge --no-ff --no-commit upstream/develop
```

Expected: merge stops on the predicted conflicts and `.git/MERGE_HEAD` points to `a752e56765...`.

- [ ] **Step 3: Capture and classify every unresolved path**

Run:

```bash
git diff --name-only --diff-filter=U
git ls-files -u
```

Expected: each path is classified into branding, core/auth, frontend/mobile, channels, configuration/schema, Enterprise/Captain, or specs.

### Task 2: Resolve branding, configuration, schema, and documentation

**Files:**
- Modify: `AGENTS.md`
- Modify: `public/manifest.json`
- Modify: `public/android-icon-*.png`
- Modify: `public/apple-icon*.png`
- Modify: `public/favicon*.png`
- Modify: `public/ms-icon-*.png`
- Modify: `config/integration/apps.yml`
- Modify: `config/schedule.yml`
- Modify: `db/schema.rb`
- Verify: `config/routes.rb`
- Verify: `config/locales/en.yml`
- Verify: `lib/redis/redis_keys.rb`

**Interfaces:**
- Consumes: Chatwit branding/integrations/schema plus upstream 4.16 migrations and schedules
- Produces: additive configuration with the upstream schema version and all fork-only entries

- [ ] **Step 1: Preserve Chatwit binary branding assets**

For each unresolved PNG under `public/`, select stage 2 (the Chatwit side), then verify its blob equals the pre-merge branch:

```bash
git checkout --ours public/android-icon-*.png public/apple-icon*.png public/favicon*.png public/ms-icon-*.png
git add public/android-icon-*.png public/apple-icon*.png public/favicon*.png public/ms-icon-*.png
```

Expected: every binary icon is resolved to the Chatwit blob, not the Chatwoot blob.

- [ ] **Step 2: Merge the PWA manifest manually**

Keep the Chatwit product name, short name, theme, icons, and standalone behavior. Add compatible upstream fields only when they do not replace Chatwit branding. Remove all conflict markers and stage `public/manifest.json`.

- [ ] **Step 3: Merge integration configuration additively**

Keep the upstream RealtimeKit migration and sensitive-field redaction changes in `config/integration/apps.yml`, plus the complete `socialwise`, `socialwise_flow`, and `jusmonitoria` entries. Keep upstream schedules and every Chatwit custom schedule in `config/schedule.yml`.

- [ ] **Step 4: Merge schema by migration history**

Use the upstream schema version and retain all columns/tables/indexes introduced by Chatwit migrations, including Captain Payment Phase 2, Evolution Go, payment links, mobile push, dossier/transcription, SocialWise ownership, and JusMonitorIA. Validate with:

```bash
bundle exec rails db:abort_if_pending_migrations
```

Expected: no pending migration discrepancy after test DB preparation.

- [ ] **Step 5: Update AGENTS migration history**

Append a 2026-07-18 entry containing upstream 4.16.0, 405 integrated commits, new merge-base `a752e567`, final conflict count, and the new protected `Llm::FeatureRouter` integration rule.

### Task 3: Resolve core authentication, jobs, webhooks, and channel conflicts

**Files:**
- Modify: `app/controllers/api/v1/accounts_controller.rb`
- Modify: `app/controllers/api/v1/notification_subscriptions_controller.rb`
- Modify: `app/controllers/concerns/access_token_auth_helper.rb`
- Modify: `app/controllers/webhooks/whatsapp_controller.rb`
- Modify: `app/jobs/hook_job.rb`
- Modify: `app/jobs/webhooks/whatsapp_events_job.rb`
- Modify: `app/listeners/hook_listener.rb`
- Verify: `app/listeners/webhook_listener.rb`
- Modify: `app/models/attachment.rb`
- Modify: `app/models/channel/whatsapp.rb`
- Modify: `app/models/inbox.rb`
- Modify: `app/services/whatsapp/facebook_api_client.rb`
- Modify: `app/services/whatsapp/incoming_message_base_service.rb`
- Modify: `app/services/whatsapp/providers/whatsapp_cloud_service.rb`
- Modify: `app/services/whatsapp/reauthorization_service.rb`
- Modify: `app/views/api/v1/models/_account.json.jbuilder`
- Modify: `app/views/devise/mailer/confirmation_instructions.html.erb`

**Interfaces:**
- Consumes: upstream API/webhook feature guards, WhatsApp coexistence/referral changes, and Chatwit transport customizations
- Produces: stable Agent Bot, webhook, SocialWise/JusMonitorIA, Cloud API, Evolution Go, and QUICK_REPLY behavior

- [ ] **Step 1: Resolve authentication without widening user tokens**

Keep upstream `api_and_webhooks` enforcement for ordinary API tokens. Preserve the exact Chatwit global Agent Bot allowlist and account-independent bot behavior in `access_token_auth_helper.rb`; no user token may replace system/bot credentials.

- [ ] **Step 2: Resolve webhook and job signatures**

Use upstream job arguments and account payload additions. Preserve SocialWise/JusMonitorIA dispatch, `include_access_token`, HMAC behavior, hook routing, and Evolution Go event routing.

- [ ] **Step 3: Resolve WhatsApp models and services**

Keep upstream coexistence/referral/embedded-signup logic. Preserve `provider: evolution_go`, nullable phone setup for that provider, `extract_interactive_data`, template dispatch, rich response metadata, typing events, and HMAC instance tokens.

- [ ] **Step 4: Add focused regression coverage where upstream changed the same branch**

Tests must assert that `create_message` still merges `extract_interactive_data(message)`, template payloads still call the template send path, and upstream coexistence/referral events remain accepted.

- [ ] **Step 5: Run the channel/core focused tests**

Run:

```bash
bundle exec rspec \
  spec/controllers/webhooks/whatsapp_controller_spec.rb \
  spec/jobs/webhooks/whatsapp_events_job_spec.rb \
  spec/listeners/webhook_listener_spec.rb \
  spec/services/whatsapp/facebook_api_client_spec.rb \
  spec/services/whatsapp/providers/whatsapp_cloud_service_spec.rb \
  spec/lib/integrations/socialwise_flow/processor_service_spec.rb \
  spec/lib/integrations/jusmonitoria/processor_service_spec.rb \
  spec/services/evolution_go/sync_state_service_spec.rb
```

Expected: zero failures.

### Task 4: Resolve frontend, rich messages, inbox configuration, and mobile isolation

**Files:**
- Modify: `app/javascript/dashboard/components-next/message/Message.vue`
- Modify: `app/javascript/dashboard/components-next/message/chips/Audio.vue`
- Modify: `app/javascript/dashboard/components/Modal.vue`
- Modify: `app/javascript/dashboard/constants/localStorage.js`
- Modify: `app/javascript/dashboard/i18n/locale/en/conversation.json`
- Modify: `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json`
- Modify: `app/javascript/dashboard/i18n/locale/pt/index.js`
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/conversation.json`
- Modify: `app/javascript/dashboard/routes/dashboard/settings/customRoles/component/CustomRolePaywall.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/settings/inbox/settingsPage/ConfigurationPage.vue`
- Verify: `app/javascript/dashboard/routes/dashboard/settings/integrations/Webhooks/WebhookForm.vue`
- Verify: `app/javascript/dashboard/routes/dashboard/Dashboard.vue`
- Verify: `app/javascript/dashboard/components-next/mobile/`
- Modify: `vite.config.ts`

**Interfaces:**
- Consumes: upstream Captain reporting/accessibility/inbox changes and Chatwit rich/mobile components
- Produces: one desktop path plus a conditionally rendered mobile PWA with unchanged stores/APIs

- [ ] **Step 1: Merge message rendering branches**

Retain upstream message reporting, overflow and shared-link fixes. Preserve routing to `WhatsAppInteractive.vue`, `RichCards.vue`, fork-only audio transcription/download controls, and existing content-type fallbacks.

- [ ] **Step 2: Merge inbox/settings and localization**

Keep upstream feature/paywall/configuration behavior and Chatwit Evolution Go, webhook access token, JusMonitorIA, mobile, and Captain Phase 2 controls. Preserve valid JSON and only intentionally modified English/Portuguese fork strings.

- [ ] **Step 3: Prove desktop/mobile isolation**

Confirm `Dashboard.vue` still renders `<MobileLayout v-if="isSmallScreen" />` and desktop paths remain in the opposite branch. Confirm mobile code imports existing stores/composables rather than duplicate transport logic.

- [ ] **Step 4: Run focused lint and component tests**

Run ESLint for every modified Vue/JS/TS file and Vitest for Captain dropdown, `useCaptain`, rich-message, audio, and mobile specs discovered by `rg --files ... | rg '(spec|test)'` within their exact component directories.

Expected: zero ESLint errors and all discovered focused specs pass.

### Task 5: Integrate upstream LLM FeatureRouter with WitDev Enterprise routing

**Files:**
- Modify: `app/controllers/api/v1/accounts/captain/preferences_controller.rb`
- Modify: `app/controllers/super_admin/app_configs_controller.rb`
- Modify: `app/models/concerns/captain_featurable.rb`
- Modify: `lib/llm/feature_router.rb`
- Verify: `lib/llm/models.rb`
- Modify: `lib/captain/base_task_service.rb`
- Modify: `enterprise/app/models/concerns/agentable.rb`
- Modify: `enterprise/app/services/llm/base_ai_service.rb`
- Modify: `enterprise/lib/enterprise/captain/reply_suggestion_service.rb`
- Modify: `enterprise/app/services/internal/accounts/internal_attributes_service.rb`
- Verify: `enterprise/app/services/captain/llm/embedding_service.rb`
- Verify: `enterprise/app/services/messages/audio_transcription_service.rb`
- Test: `spec/lib/llm/feature_router_spec.rb`
- Test: `spec/controllers/api/v1/accounts/captain/preferences_controller_spec.rb`
- Test: `spec/lib/captain/base_task_service_spec.rb`
- Test: `spec/enterprise/models/concerns/agentable_spec.rb`
- Test: `spec/enterprise/services/llm/base_ai_service_spec.rb`
- Test: `spec/enterprise/services/captain/llm/embedding_service_spec.rb`
- Test: `spec/enterprise/services/messages/audio_transcription_service_spec.rb`

**Interfaces:**
- Consumes: `Chatwit::CaptainModelResolver#resolve!`, `Chatwit::LlmProxy.route_witdev?`, and upstream `Llm::FeatureRouter.resolve(feature:, account:)`
- Produces: `{ feature:, provider:, model:, source: }` for both legacy and WitDev routes without fallback leakage

- [ ] **Step 1: Write failing FeatureRouter route tests**

Add examples equivalent to:

```ruby
context 'when the WitDev route is selected' do
  it 'resolves a generative account override through the canonical resolver' do
    allow(Chatwit::LlmProxy).to receive(:route_witdev?).and_return(true)
    account.captain_models = { 'assistant' => 'witdev_claude/sonnet' }
    allow_any_instance_of(Chatwit::CaptainModelResolver)
      .to receive(:resolve!).with('assistant').and_return('witdev_claude/sonnet')

    expect(described_class.resolve(feature: :assistant, account: account)).to include(
      model: 'witdev_claude/sonnet', source: :account_override
    )
  end

  it 'does not route embeddings through the WitDev generative resolver' do
    allow(Chatwit::LlmProxy).to receive(:route_witdev?).and_return(true)

    expect(described_class.resolve(feature: :help_center_search, account: account)[:model])
      .to eq('text-embedding-3-small')
  end
end
```

Run the new examples and expect the first one to fail before implementation because upstream's router rejects the canonical alias.

- [ ] **Step 2: Implement the dual-route FeatureRouter boundary**

Implement this behavior in `lib/llm/feature_router.rb`:

```ruby
def resolve(feature:, account: nil)
  feature_key = feature.to_s
  raise UnknownFeatureError, "Unknown LLM feature: #{feature_key}" unless Llm::Models.feature?(feature_key)
  return resolve_witdev(feature_key, account) if witdev_generative_feature?(feature_key)

  resolve_legacy(feature_key, account)
end

def resolve_witdev(feature_key, account)
  resolver = Chatwit::CaptainModelResolver.new(account: account)
  model = resolver.resolve!(feature_key)
  descriptor = Chatwit::LlmProxy.operational_models.find { |entry| entry['value'] == model }
  source = account&.captain_models&.[](feature_key).present? ? :account_override : :witdev_default
  { feature: feature_key, provider: descriptor&.dig('provider'), model: model, source: source }
end
```

Keep upstream's existing resolution body in `resolve_legacy` and define
`witdev_generative_feature?` as the conjunction of `route_witdev?` and
`Chatwit::CaptainModelResolver.generative_feature?`.

- [ ] **Step 3: Merge preference validation and normalization**

Keep upstream dynamic feature keys, `compact_blank`, clearing semantics and Captain V2 defaults. In WitDev mode, expose only operational catalog models for generative features and validate each submitted alias with `CaptainModelResolver#validate!`. Rescue catalog/model errors as 422 without changing stored preferences.

- [ ] **Step 4: Merge runtime credentials and endpoint selection**

`Captain::BaseTaskService` must call `Llm::FeatureRouter`, use `Chatwit::LlmProxy.api_base` and proxy key for WitDev, retain upstream hook/system credentials for legacy, and rescue canonical catalog errors as 422. `Concerns::Agentable` and `Llm::BaseAiService` must prefer the router result unconditionally for a WitDev generative route so installation defaults cannot override it.

- [ ] **Step 5: Preserve legacy-only transports**

Confirm `embedding_service.rb` still uses upstream/OpenAI legacy credentials, native audio transcription keeps the upstream 25 MB/temperature/model-limit changes, and Chatwit proxy transcription remains separately guarded by its operational catalog and audio allowlist.

- [ ] **Step 6: Run the complete Captain/Enterprise routing matrix**

Run all specs under `spec/enterprise` whose paths contain `captain`, plus:

```bash
bundle exec rspec \
  spec/controllers/api/v1/accounts/captain/preferences_controller_spec.rb \
  spec/lib/chatwit/llm_proxy_spec.rb \
  spec/lib/chatwit/captain_model_resolver_spec.rb \
  spec/lib/llm/feature_router_spec.rb \
  spec/lib/llm/models_spec.rb \
  spec/lib/llm/config_spec.rb \
  spec/enterprise/models/concerns/agentable_spec.rb \
  spec/enterprise/services/llm/base_ai_service_spec.rb \
  spec/enterprise/services/messages/audio_transcription_service_spec.rb \
  spec/enterprise/integration/captain_payment_phase2_spec.rb
```

Expected: route `chatwoot` uses upstream defaults/hooks, route `witdev` uses canonical aliases/proxy, unavailable catalog fails closed, and all tests pass.

### Task 6: Resolve remaining specs and prove the merge is structurally clean

**Files:**
- Modify: `spec/controllers/super_admin/app_config_controller_spec.rb`
- Modify: `spec/enterprise/models/concerns/agentable_spec.rb`
- Modify: `spec/enterprise/services/captain/llm/embedding_service_spec.rb`
- Modify: `spec/enterprise/services/messages/audio_transcription_service_spec.rb`
- Modify: `spec/jobs/webhooks/whatsapp_events_job_spec.rb`
- Modify: `spec/lib/captain/reply_suggestion_service_spec.rb`
- Modify: `spec/services/whatsapp/facebook_api_client_spec.rb`
- Modify: `spec/services/whatsapp/providers/whatsapp_cloud_service_spec.rb`
- Verify: every path reported by `git diff --name-only --diff-filter=U`

**Interfaces:**
- Consumes: resolved production behavior from Tasks 2–5
- Produces: no unmerged entries and tests that cover both upstream and fork behavior

- [ ] **Step 1: Merge specs additively**

Retain upstream examples and Chatwit examples. Deduplicate only identical setup; never delete an assertion merely to make the suite green.

- [ ] **Step 2: Remove all unmerged index entries**

Run:

```bash
git diff --name-only --diff-filter=U
git ls-files -u
```

Expected: both outputs empty.

- [ ] **Step 3: Scan for conflict markers**

Run `rg -n '^(<<<<<<<|=======|>>>>>>>)'` across tracked Ruby, Vue, JS, TS, YAML, JSON, ERB, HTML and Markdown files, excluding fixture content that intentionally tests markers.

Expected: zero merge markers in application/configuration code.

- [ ] **Step 4: Create the upstream merge commit**

Run:

```bash
git commit -m "merge(upstream): sync Chatwoot 4.16.0"
```

Expected: a two-parent merge commit whose second parent is `a752e56765...`.

### Task 7: Run broad OSS, Enterprise, frontend, migration, and fork-only validation

**Files:**
- Verify: all changed Ruby/Vue/JS/TS files
- Verify: `spec/enterprise/`
- Verify: protected files listed in `.agents/skills/chatwit-upstream-sync/SKILL.md`

**Interfaces:**
- Consumes: completed merge commit
- Produces: evidence sufficient to permit integration and production build

- [ ] **Step 1: Reinstall exact merged dependencies**

Run `bundle check || bundle install` and `pnpm install --frozen-lockfile`.

- [ ] **Step 2: Prepare and validate the test database**

Run with PostgreSQL/Redis on `127.0.0.1` and no `.env`:

```bash
RAILS_ENV=test bundle exec rails db:prepare
RAILS_ENV=test bundle exec rails db:abort_if_pending_migrations
```

- [ ] **Step 3: Run Ruby quality and behavioral suites**

Run RuboCop on every changed Ruby file. Run all Captain Enterprise specs, all fork-only specs discovered under SocialWise/JusMonitorIA/Evolution Go/WhatsApp/webhooks/rich messages/mobile support, then run the broader affected controller/model/job/service suites. Every failure must be classified and fixed before proceeding.

- [ ] **Step 4: Run frontend quality and tests**

Run ESLint on every changed Vue/JS/TS file, the focused Vitest matrix, then `pnpm test` if the focused matrix is green.

- [ ] **Step 5: Verify protected customizations structurally**

Check every path and invariant in the upstream-sync skill, plus `config/initializers/00_chatwit.rb`, `components-next/mobile`, Captain Payment Phase 2, and LLM canonical routing. Confirm `extract_interactive_data` is invoked by message creation and Chatwit logo/icon hashes match the backup branch.

- [ ] **Step 6: Verify history and perform final diff review**

Run:

```bash
git rev-list --count HEAD..upstream/develop
git merge-base HEAD upstream/develop
git diff --check backup/pre-upstream-sync-20260718..HEAD
git status --short
```

Expected: upstream-ahead `0`, merge-base `a752e56765...`, no whitespace errors, clean branch.

### Task 8: Document, integrate into develop, push, build, and validate production

**Files:**
- Modify: `AGENTS.md`
- Create: `chatwitdocs/upstream-sync-v4.16.0.md`

**Interfaces:**
- Consumes: verified sync branch and user's pre-approved production authority
- Produces: `origin/develop` and production app/Sidekiq on the same immutable image digest

- [ ] **Step 1: Record final sync evidence**

Document commit counts, merge-base, every conflict resolution group, Enterprise/Captain compatibility, protected-feature audit, validation results, and production rollback reference. Update the AGENTS history with exact final values.

- [ ] **Step 2: Commit documentation changes**

Run:

```bash
git add AGENTS.md chatwitdocs/upstream-sync-v4.16.0.md
git commit -m "docs(sync): record Chatwoot 4.16 migration"
```

- [ ] **Step 3: Review and integrate locally into develop**

Preserve the dirty main checkout in a recoverable stash, fast-forward/merge the verified sync branch into local `develop`, restore all unrelated local changes, and verify their content hashes. Push with `git push origin develop` and confirm local/remote SHAs match.

- [ ] **Step 4: Build and deploy production**

With the main checkout clean of unrelated files during build, run `./build.sh`. Follow image build, immutable tag and `latest` pushes, and Portainer updates through completion. Evolution Go may be skipped only if its source/dependencies were unchanged by the upstream sync.

- [ ] **Step 5: Prove production convergence**

Verify through SSH that `chatwoot_app_chatwoot_app` and `chatwoot_app_chatwoot_sidekiq` have `UpdateStatus=completed`, use the immutable new digest, and have stable `Running` tasks without recent fatal boot errors. Verify `https://chatwit.witdev.com.br` returns HTTP 200.

- [ ] **Step 6: Complete the goal only after requirement-by-requirement audit**

Match each design criterion to direct evidence: upstream ancestry, zero conflicts, Enterprise/Captain tests, fork-only checks, pushed SHA, registry digest, Swarm services, and public HTTP health. Do not mark complete with missing or indirect evidence.
