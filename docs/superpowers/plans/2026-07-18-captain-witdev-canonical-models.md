# Captain WitDev Canonical Models Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `CAPTAIN_LLM_ROUTE=witdev` list, persist, validate, and execute only canonical aliases from `platform-api /api/v1/llm/models`, while leaving the Chatwoot legacy route unchanged.

**Architecture:** `Chatwit::LlmProxy` remains the only adapter to the central catalog and separates presentation data from operational authorization. A new `Chatwit::CaptainModelResolver` owns per-account feature selection and fallback to `CAPTAIN_WITDEV_MODEL`; controllers and runtime services call it only on the WitDev route, while legacy callers continue using `Llm::Models` and existing provider keys.

**Tech Stack:** Ruby 3/Rails, HTTParty, RubyLLM, OpenAI-compatible LiteLLM proxy, Vue 3 `<script setup>`, Pinia, Vitest, RSpec.

## Global Constraints

- Read `/home/wital/witdev-platform-core/docs/LLM-CANONICAL-FLOW-ALL-APPS.md` before execution.
- Work in an isolated Chatwit worktree created with `superpowers:using-git-worktrees`; do not alter the dirty `/home/wital/chatwit` checkout.
- `platform-api /api/v1/llm/models` is the only model-listing contract; never call LiteLLM or OmniRoute directly for listing.
- Persist only the exact canonical `value`/`alias`.
- A model authorizes execution only when the catalog source is `litellm_proxy`, the alias is present, `active != false`, and `hidden != true`.
- Never merge `config/llm.yml` models into a WitDev generative feature.
- `CAPTAIN_LLM_ROUTE=chatwoot`, embeddings, OpenAI Files, and native `whisper-1` behavior must remain unchanged.
- Browser code must never receive proxy credentials or internal platform URLs.
- Follow TDD: add one failing expectation, run it and observe the expected failure, then write production code.
- Use `apply_patch` for edits. Do not commit or push unless the user explicitly authorizes it; each task ends with a diff checkpoint instead.
- Run Ruby specs without `.env`, after `eval "$(rbenv init -)"`, using the shared PostgreSQL/Redis endpoints from `AGENTS.md`.
- Update only English frontend translations.

---

### Task 1: Canonical catalog contract and fail-closed resolver primitives

**Files:**
- Create: `spec/lib/chatwit/llm_proxy_spec.rb`
- Modify: `lib/chatwit/llm_proxy.rb`

**Interfaces:**
- Consumes: `GET Chatwit::LlmProxy.catalog_url`, returning the platform catalog payload.
- Produces:
  - `Chatwit::LlmProxy.catalog #=> { 'models' => Array<Hash>, 'source' => String }`
  - `Chatwit::LlmProxy.catalog_models #=> Array<Hash>`
  - `Chatwit::LlmProxy.catalog_source #=> String`
  - `Chatwit::LlmProxy.operational_catalog? #=> Boolean`
  - `Chatwit::LlmProxy.operational_models #=> Array<Hash>`
  - `Chatwit::LlmProxy.resolve_model!(alias_name) #=> String`
  - `Chatwit::LlmProxy::CatalogUnavailableError`
  - `Chatwit::LlmProxy::ModelUnavailableError`

- [ ] **Step 1: Write failing catalog normalization and authorization specs**

Create `spec/lib/chatwit/llm_proxy_spec.rb` with these examples:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Chatwit::LlmProxy do
  around do |example|
    previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = previous_cache
  end

  let(:response) { instance_double(HTTParty::Response, success?: true, parsed_response: payload) }
  let(:model) do
    {
      'value' => 'witdev_claude/sonnet',
      'label' => 'Claude Sonnet',
      'provider' => 'witdev_claude',
      'providerLabel' => 'WitDev Claude Code',
      'source' => 'litellm_proxy',
      'active' => true,
      'hidden' => false,
      'supportsTools' => true,
      'supportsJsonSchema' => true,
      'recommendedFor' => ['captain']
    }
  end
  let(:payload) { { 'source' => 'litellm_proxy', 'models' => [model] } }

  before do
    allow(described_class).to receive(:catalog_url).and_return('http://platform-api:8000/api/v1/llm/models')
    allow(HTTParty).to receive(:get).and_return(response)
  end

  it 'preserves the central source and authorization metadata' do
    expect(described_class.catalog_source).to eq('litellm_proxy')
    expect(described_class.catalog_models.first).to include(
      'value' => 'witdev_claude/sonnet',
      'provider' => 'witdev_claude',
      'provider_label' => 'WitDev Claude Code',
      'source' => 'litellm_proxy',
      'active' => true,
      'hidden' => false,
      'supports_tools' => true,
      'supports_json_schema' => true,
      'recommended_for' => ['captain']
    )
  end

  it 'resolves an active visible alias from the operational catalog' do
    expect(described_class.resolve_model!('witdev_claude/sonnet')).to eq('witdev_claude/sonnet')
  end

  it 'does not authorize a non-operational fallback source' do
    payload['source'] = 'legacy_socialwise'

    expect(described_class.operational_models).to eq([])
    expect { described_class.resolve_model!('witdev_claude/sonnet') }
      .to raise_error(Chatwit::LlmProxy::CatalogUnavailableError)
  end

  it 'rejects a hidden, inactive, or absent alias' do
    model['hidden'] = true

    expect { described_class.resolve_model!('witdev_claude/sonnet') }
      .to raise_error(Chatwit::LlmProxy::ModelUnavailableError)
  end

  it 'returns an unavailable catalog for HTTP failure' do
    allow(response).to receive(:success?).and_return(false)

    expect(described_class.catalog).to eq('models' => [], 'source' => 'unavailable')
  end
end
```

- [ ] **Step 2: Run the new specs and verify RED**

Run:

```bash
eval "$(rbenv init -)"
POSTGRES_HOST=127.0.0.1 POSTGRES_PORT=5432 POSTGRES_USERNAME=postgres POSTGRES_PASSWORD=postgres \
REDIS_URL=redis://127.0.0.1:6379/0 bundle exec rspec spec/lib/chatwit/llm_proxy_spec.rb
```

Expected: failures for missing `catalog`, `catalog_source`, `operational_models`, `resolve_model!`, and error classes.

- [ ] **Step 3: Implement the catalog object and authorization methods**

In `lib/chatwit/llm_proxy.rb`:

```ruby
OPERATIONAL_CATALOG_SOURCE = 'litellm_proxy'.freeze
CATALOG_CACHE_KEY = 'chatwit:witdev_llm_catalog:v2'.freeze

class CatalogUnavailableError < StandardError; end
class ModelUnavailableError < StandardError; end

def catalog
  Rails.cache.fetch(CATALOG_CACHE_KEY, expires_in: CATALOG_CACHE_TTL) { fetch_catalog }
rescue StandardError => e
  Rails.logger.error "[CHATWIT][LLM_PROXY] catalog fetch failed: #{e.message}"
  unavailable_catalog
end

def catalog_models
  catalog.fetch('models')
end

def catalog_source
  catalog.fetch('source')
end

def operational_catalog?
  catalog_source == OPERATIONAL_CATALOG_SOURCE
end

def operational_models
  return [] unless operational_catalog?

  catalog_models.select { |entry| entry['active'] != false && entry['hidden'] != true }
end

def resolve_model!(alias_name)
  raise CatalogUnavailableError, 'The canonical LLM catalog is unavailable' unless operational_catalog?

  candidate = alias_name.to_s.presence
  entry = operational_models.find { |model_entry| model_entry['value'] == candidate }
  raise ModelUnavailableError, "LLM model alias is unavailable: #{candidate.presence || '(blank)'}" unless entry

  entry.fetch('value')
end
```

Replace `fetch_catalog_models` with:

```ruby
def fetch_catalog
  response = HTTParty.get(catalog_url, timeout: CATALOG_TIMEOUT_SECONDS)
  return unavailable_catalog unless response.success?

  payload = response.parsed_response
  return unavailable_catalog unless payload.is_a?(Hash) && payload['models'].is_a?(Array)

  models = payload['models'].filter_map { |entry| catalog_entry(entry) }
  return unavailable_catalog if models.empty?

  { 'models' => models, 'source' => payload['source'].presence || 'unavailable' }
end

def unavailable_catalog
  { 'models' => [], 'source' => 'unavailable' }
end
```

Make `catalog_entry` preserve the published descriptor instead of reconstructing metadata:

```ruby
def catalog_entry(entry)
  value = entry['value'].presence || entry['alias'].presence
  return if value.blank?

  {
    'value' => value,
    'label' => entry['label'].presence || entry['displayName'].presence || value,
    'provider' => entry['provider'],
    'provider_label' => entry['providerLabel'].presence || entry['provider'],
    'source' => entry['source'],
    'active' => entry.fetch('active', true),
    'hidden' => entry.fetch('hidden', false),
    'supports_reasoning' => entry['supportsReasoning'] == true,
    'supports_vision' => entry['supportsVision'] == true,
    'supports_json_schema' => entry['supportsJsonSchema'] == true,
    'supports_tools' => entry['supportsTools'] == true,
    'supports_embeddings' => entry['supportsEmbeddings'] == true,
    'recommended_for' => Array(entry['recommendedFor']),
    'input_cost_per_1m' => entry['inputCostPer1M'],
    'output_cost_per_1m' => entry['outputCostPer1M'],
    'context_window' => entry['contextWindow']
  }
end
```

Update `register_models!` so it registers only `operational_models`; never union an unverified configured alias into the registry.

- [ ] **Step 4: Run the focused spec and verify GREEN**

Run the command from Step 2. Expected: all examples pass.

- [ ] **Step 5: Review checkpoint without commit**

Run:

```bash
git diff --check -- lib/chatwit/llm_proxy.rb spec/lib/chatwit/llm_proxy_spec.rb
git diff -- lib/chatwit/llm_proxy.rb spec/lib/chatwit/llm_proxy_spec.rb
```

Expected: no whitespace errors; diff contains only the canonical catalog contract and its specs.

---

### Task 2: Route-aware per-account Captain model resolver and preferences API

**Files:**
- Create: `lib/chatwit/captain_model_resolver.rb`
- Create: `spec/lib/chatwit/captain_model_resolver_spec.rb`
- Modify: `app/models/concerns/captain_featurable.rb`
- Modify: `app/controllers/api/v1/accounts/captain/preferences_controller.rb`
- Modify: `spec/models/concerns/captain_featurable_spec.rb`
- Modify: `spec/controllers/api/v1/accounts/captain/preferences_controller_spec.rb`

**Interfaces:**
- Consumes: Task 1 `operational_models`, `resolve_model!`, `catalog_source`, and `model`.
- Produces:
  - `Chatwit::CaptainModelResolver::GENERATIVE_FEATURES`
  - `Chatwit::CaptainModelResolver#selected_alias(feature)`
  - `Chatwit::CaptainModelResolver#resolve!(feature)`
  - `Chatwit::CaptainModelResolver#validate!(feature, alias_name)`
  - `Chatwit::CaptainModelResolver#feature_config(feature)`
  - `Chatwit::CaptainModelResolver#model_options`
  - `Chatwit::CaptainModelResolver#models_payload`
  - `Chatwit::CaptainModelResolver#providers_payload`
  - route-aware `captain/preferences` payload with `catalog.route`, `catalog.source`, and `catalog.operational`.

- [ ] **Step 1: Write failing resolver specs**

Create `spec/lib/chatwit/captain_model_resolver_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Chatwit::CaptainModelResolver do
  let(:account) { create(:account, captain_models: { 'editor' => 'witdev/gpt-5.5' }) }
  let(:resolver) { described_class.new(account: account) }
  let(:models) do
    [{ 'value' => 'witdev/gpt-5.5', 'label' => 'GPT-5.5', 'provider' => 'witdev',
       'provider_label' => 'WitDev Codex', 'active' => true, 'hidden' => false }]
  end

  before do
    allow(Chatwit::LlmProxy).to receive(:model).and_return('witdev_claude/sonnet')
    allow(Chatwit::LlmProxy).to receive(:operational_models).and_return(models)
    allow(Chatwit::LlmProxy).to receive(:resolve_model!) { |alias_name| alias_name }
  end

  it 'uses the account alias before the global alias' do
    expect(resolver.selected_alias(:editor)).to eq('witdev/gpt-5.5')
    expect(resolver.resolve!(:editor)).to eq('witdev/gpt-5.5')
  end

  it 'uses the global alias when the account has no feature selection' do
    expect(resolver.selected_alias(:assistant)).to eq('witdev_claude/sonnet')
  end

  it 'builds feature options from central descriptors' do
    expect(resolver.feature_config(:editor)).to include(
      default: 'witdev_claude/sonnet',
      selected: 'witdev/gpt-5.5',
      selection_valid: true
    )
    expect(resolver.feature_config(:editor)[:models].first).to include(
      id: 'witdev/gpt-5.5', display_name: 'GPT-5.5', provider: 'witdev'
    )
  end

  it 'delegates exact alias validation to the proxy catalog' do
    expect(Chatwit::LlmProxy).to receive(:resolve_model!).with('witdev/gpt-5.5')
    resolver.validate!(:editor, 'witdev/gpt-5.5')
  end
end
```

- [ ] **Step 2: Add failing request/model examples for route separation**

In `spec/controllers/api/v1/accounts/captain/preferences_controller_spec.rb`, add a WitDev context that stubs `route_witdev?` true, returns one operational descriptor, and verifies:

```ruby
expect(json_response.dig(:catalog, :route)).to eq('witdev')
expect(json_response.dig(:catalog, :source)).to eq('litellm_proxy')
expect(json_response.dig(:features, :editor, :models, 0, :id)).to eq('witdev/gpt-5.5')
```

Add PUT examples that accept `witdev/gpt-5.5` when `resolve_model!` succeeds and return `:unprocessable_entity` without changing `account.captain_models` when `resolve_model!` raises `ModelUnavailableError`.

In `spec/models/concerns/captain_featurable_spec.rb`, add one WitDev example proving a canonical `editor` alias is not validated against `config/llm.yml`, and retain the existing invalid legacy model example under `route_witdev? == false`.

- [ ] **Step 3: Run the focused specs and verify RED**

```bash
eval "$(rbenv init -)"
POSTGRES_HOST=127.0.0.1 POSTGRES_PORT=5432 POSTGRES_USERNAME=postgres POSTGRES_PASSWORD=postgres \
REDIS_URL=redis://127.0.0.1:6379/0 bundle exec rspec \
spec/lib/chatwit/captain_model_resolver_spec.rb \
spec/controllers/api/v1/accounts/captain/preferences_controller_spec.rb \
spec/models/concerns/captain_featurable_spec.rb
```

Expected: missing resolver constant/class and missing route-aware response failures.

- [ ] **Step 4: Implement `Chatwit::CaptainModelResolver`**

Create `lib/chatwit/captain_model_resolver.rb`:

```ruby
# frozen_string_literal: true

class Chatwit::CaptainModelResolver
  GENERATIVE_FEATURES = %w[editor assistant copilot label_suggestion].freeze

  def initialize(account:)
    @account = account
  end

  def self.generative_feature?(feature)
    GENERATIVE_FEATURES.include?(feature.to_s)
  end

  def selected_alias(feature)
    stored_models[feature.to_s].presence || Chatwit::LlmProxy.model
  end

  def resolve!(feature)
    Chatwit::LlmProxy.resolve_model!(selected_alias(feature))
  end

  def validate!(feature, alias_name)
    return unless self.class.generative_feature?(feature)

    Chatwit::LlmProxy.resolve_model!(alias_name)
  end

  def feature_config(feature)
    feature_name = feature.to_s
    return legacy_feature_config(feature_name) unless self.class.generative_feature?(feature_name)

    selected = selected_alias(feature_name)
    {
      models: model_options,
      default: Chatwit::LlmProxy.model,
      selected: selected,
      selection_valid: Chatwit::LlmProxy.operational_models.any? { |entry| entry['value'] == selected },
      enabled: account.captain_preferences[:features][feature_name] == true
    }
  end

  def model_options
    Chatwit::LlmProxy.operational_models.map { |entry| model_option(entry) }
  end

  def models_payload
    model_options.index_by { |option| option.fetch(:id) }
  end

  def providers_payload
    Chatwit::LlmProxy.operational_models.each_with_object({}) do |entry, providers|
      provider = entry['provider'].presence || 'unknown'
      providers[provider] ||= { display_name: entry['provider_label'].presence || provider }
    end
  end

  private

  attr_reader :account

  def stored_models
    account.captain_models || {}
  end

  def legacy_feature_config(feature)
    config = Llm::Models.feature_config(feature)
    preferences = account.captain_preferences
    config.merge(
      enabled: preferences[:features][feature] == true,
      selected: preferences[:models][feature],
      selection_valid: true
    )
  end

  def model_option(entry)
    {
      id: entry['value'],
      display_name: entry['label'],
      provider: entry['provider'],
      provider_label: entry['provider_label'],
      coming_soon: false,
      credit_multiplier: nil
    }
  end
end
```

- [ ] **Step 5: Make `CaptainFeaturable` route-aware without changing legacy behavior**

Refactor `captain_models_with_defaults` so only WitDev generative keys use stored alias → global alias. Keep the exact current `Llm::Models.valid_model_for?` branch for all legacy-route keys and for `audio_transcription`/`help_center_search`:

```ruby
if Chatwit::LlmProxy.route_witdev? && Chatwit::CaptainModelResolver.generative_feature?(feature_key)
  result[feature_key] = stored_value.presence || Chatwit::LlmProxy.model
elsif stored_value.present? && Llm::Models.valid_model_for?(feature_key, stored_value)
  result[feature_key] = stored_value
else
  result[feature_key] = Llm::Models.default_model_for(feature_key)
end
```

In `validate_captain_models`, skip only generative keys when `route_witdev?`; their write path is validated by the preferences controller and their runtime path is validated again by the resolver. Continue the existing local validation for every other key.

- [ ] **Step 6: Implement the route-aware preferences controller**

Keep the current payload in a `legacy_preferences_payload` method. Add a WitDev payload whose generative feature configs come from `Chatwit::CaptainModelResolver` and whose non-generative configs come from `Llm::Models`:

```ruby
def preferences_payload
  return legacy_preferences_payload unless Chatwit::LlmProxy.route_witdev?

  resolver = Chatwit::CaptainModelResolver.new(account: @current_account)
  {
    providers: resolver.providers_payload,
    models: resolver.models_payload,
    features: Llm::Models.feature_keys.index_with { |feature| resolver.feature_config(feature) },
    catalog: {
      route: 'witdev',
      source: Chatwit::LlmProxy.catalog_source,
      operational: Chatwit::LlmProxy.operational_catalog?
    }
  }
end
```

Before merging incoming Captain models, validate only incoming generative keys:

```ruby
def validate_witdev_models!(models)
  return unless Chatwit::LlmProxy.route_witdev?

  resolver = Chatwit::CaptainModelResolver.new(account: @current_account)
  models.each { |feature, alias_name| resolver.validate!(feature, alias_name) }
end
```

Rescue Task 1 catalog/model errors and render `{ error: error.message }` with status 422. Do not rescue or alter the legacy ActiveRecord validation path.

- [ ] **Step 7: Run focused specs and verify GREEN**

Run the command from Step 3. Expected: all new WitDev examples and all existing legacy examples pass.

- [ ] **Step 8: Review checkpoint without commit**

```bash
git diff --check -- lib/chatwit/captain_model_resolver.rb app/models/concerns/captain_featurable.rb \
app/controllers/api/v1/accounts/captain/preferences_controller.rb spec/lib/chatwit/captain_model_resolver_spec.rb \
spec/models/concerns/captain_featurable_spec.rb spec/controllers/api/v1/accounts/captain/preferences_controller_spec.rb
```

Expected: no whitespace errors and no changes to `config/llm.yml`.

---

### Task 3: Runtime selection by Captain feature and strict route separation

**Files:**
- Modify: `lib/captain/base_task_service.rb`
- Modify: `lib/captain/reply_suggestion_service.rb`
- Modify: `lib/captain/label_suggestion_service.rb`
- Modify: `enterprise/lib/captain/conversation_completion_service.rb`
- Modify: `enterprise/app/models/concerns/agentable.rb`
- Modify: `enterprise/app/services/llm/base_ai_service.rb`
- Modify: `lib/llm/config.rb`
- Modify: `config/initializers/ai_agents.rb`
- Modify: `spec/lib/captain/base_task_service_spec.rb`
- Modify: `spec/lib/captain/reply_suggestion_service_spec.rb`
- Modify: `spec/lib/captain/label_suggestion_service_spec.rb`
- Modify: `spec/enterprise/lib/captain/conversation_completion_service_spec.rb`
- Modify: `spec/enterprise/models/concerns/agentable_spec.rb`
- Modify: `spec/enterprise/services/llm/base_ai_service_spec.rb`

**Interfaces:**
- Consumes: Task 2 `CaptainModelResolver#resolve!`.
- Produces: `Captain::BaseTaskService#make_api_call(..., feature: :editor)` and strict WitDev credential/base selection driven by `route_witdev?`.

- [ ] **Step 1: Add failing BaseTaskService routing specs**

Add contexts to `spec/lib/captain/base_task_service_spec.rb` that verify:

```ruby
allow(Chatwit::LlmProxy).to receive(:route_witdev?).and_return(true)
resolver = instance_double(Chatwit::CaptainModelResolver, resolve!: 'witdev/gpt-5.5')
allow(Chatwit::CaptainModelResolver).to receive(:new).with(account: account).and_return(resolver)

expect(resolver).to receive(:resolve!).with(:editor)
expect(mock_context).to receive(:chat).with(model: 'witdev/gpt-5.5').and_return(mock_chat)
```

Add a failing example where `resolve!` raises `ModelUnavailableError` and assert `make_api_call` returns error code 422 without invoking `Llm::Config.with_api_key`.

Add a missing-proxy-key example proving the WitDev route does not fall through to hook/system credentials.

- [ ] **Step 2: Add failing feature mapping and Agentable specs**

In reply suggestion specs, expect `make_api_call` to receive `feature: :copilot`; in label suggestion specs expect `feature: :label_suggestion`; in conversation completion specs expect `feature: :assistant`.

In `spec/enterprise/models/concerns/agentable_spec.rb`, give the dummy class an `account` and verify `agent_model` calls `CaptainModelResolver#resolve!(:assistant)` when `route_witdev?` is true, while retaining every current legacy expectation when false.

In `spec/enterprise/services/llm/base_ai_service_spec.rb`, verify the WitDev branch calls `Chatwit::LlmProxy.resolve_model!(Chatwit::LlmProxy.model)` and the legacy branch remains unchanged.

- [ ] **Step 3: Run the runtime specs and verify RED**

```bash
eval "$(rbenv init -)"
POSTGRES_HOST=127.0.0.1 POSTGRES_PORT=5432 POSTGRES_USERNAME=postgres POSTGRES_PASSWORD=postgres \
REDIS_URL=redis://127.0.0.1:6379/0 bundle exec rspec \
spec/lib/captain/base_task_service_spec.rb \
spec/lib/captain/reply_suggestion_service_spec.rb \
spec/lib/captain/label_suggestion_service_spec.rb \
spec/enterprise/lib/captain/conversation_completion_service_spec.rb \
spec/enterprise/models/concerns/agentable_spec.rb \
spec/enterprise/services/llm/base_ai_service_spec.rb
```

Expected: failures because `feature:` is unsupported and runtime still overwrites with the global alias.

- [ ] **Step 4: Resolve BaseTaskService models by feature**

Change the method signature and first branch:

```ruby
def make_api_call(model:, messages:, schema: nil, tools: [], feature: :editor)
  model = resolve_request_model(model, feature)

  return { error: I18n.t('captain.disabled'), error_code: 403 } unless captain_tasks_enabled?
  return { error: I18n.t('captain.api_key_missing'), error_code: 401 } unless api_key_configured?

  instrumentation_params = build_instrumentation_params(model, messages)
  instrumentation_method = tools.any? ? :instrument_tool_session : :instrument_llm_call
  response = send(instrumentation_method, instrumentation_params) do
    execute_ruby_llm_request(model: model, messages: messages, schema: schema, tools: tools)
  end

  return response unless build_follow_up_context? && response[:message].present?

  response.merge(follow_up_context: build_follow_up_context(messages, response))
rescue Chatwit::LlmProxy::CatalogUnavailableError, Chatwit::LlmProxy::ModelUnavailableError => e
  { error: e.message, error_code: 422, request_messages: messages }
end

def resolve_request_model(legacy_model, feature)
  return legacy_model unless Chatwit::LlmProxy.route_witdev?

  Chatwit::CaptainModelResolver.new(account: account).resolve!(feature)
end
```

Use `route_witdev?` in `api_base`. Make `llm_credential` exclusive:

```ruby
def llm_credential
  @llm_credential ||= if Chatwit::LlmProxy.route_witdev?
                        witdev_llm_credential
                      else
                        hook_llm_credential || system_llm_credential
                      end
end
```

`witdev_llm_credential` returns a hash only when the proxy key is present. It must never call the legacy credential methods.

- [ ] **Step 5: Connect feature-specific callers**

Add `feature: :copilot` in `Captain::ReplySuggestionService`, `feature: :label_suggestion` in `Captain::LabelSuggestionService`, and `feature: :assistant` in `Captain::ConversationCompletionService`. Leave rewrite, summary, follow-up, and other generic editor tasks on the default `:editor`.

In `Concerns::Agentable`:

```ruby
def agent_model
  return Chatwit::CaptainModelResolver.new(account: account).resolve!(:assistant) if Chatwit::LlmProxy.route_witdev?

  InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || LlmConstants::DEFAULT_MODEL
end
```

- [ ] **Step 6: Prevent incomplete WitDev configuration from falling back to legacy**

Use `route_witdev?` rather than `enabled?` for provider selection in `Llm::Config`, `Llm::BaseAiService`, and `config/initializers/ai_agents.rb`.

In `Llm::BaseAiService#setup_model`, resolve the global alias:

```ruby
if Chatwit::LlmProxy.route_witdev?
  @model = Chatwit::LlmProxy.resolve_model!(Chatwit::LlmProxy.model)
  return
end
```

In the agents initializer, configure only proxy key/base and the resolved global alias for the WitDev route. Let the existing initializer rescue log invalid/missing configuration; do not execute the legacy `else` branch when the selected route is WitDev.

Task 1's `register_models!` implementation must register only `operational_models`. The existing `zz_chatwit_llm_registry.rb` initializer remains unchanged and continues calling that public method.

- [ ] **Step 7: Run runtime specs and verify GREEN**

Run the command from Step 3. Expected: all route/feature examples pass.

- [ ] **Step 8: Run legacy regression specs**

```bash
eval "$(rbenv init -)"
POSTGRES_HOST=127.0.0.1 POSTGRES_PORT=5432 POSTGRES_USERNAME=postgres POSTGRES_PASSWORD=postgres \
REDIS_URL=redis://127.0.0.1:6379/0 bundle exec rspec \
spec/lib/captain/rewrite_service_spec.rb \
spec/lib/captain/summary_service_spec.rb \
spec/lib/captain/follow_up_service_spec.rb \
spec/enterprise/lib/captain/base_task_service_spec.rb
```

Expected: all existing legacy behavior passes.

- [ ] **Step 9: Review checkpoint without commit**

```bash
git diff --check -- lib/captain enterprise/lib/captain enterprise/app/models/concerns/agentable.rb \
enterprise/app/services/llm/base_ai_service.rb lib/llm/config.rb config/initializers/ai_agents.rb \
lib/chatwit/llm_proxy.rb
```

Expected: no whitespace errors; every new route branch is conditioned by `route_witdev?`.

---

### Task 4: Validate global, phase-2, and Captain Whisper aliases

**Files:**
- Modify: `app/controllers/super_admin/app_configs_controller.rb`
- Modify: `spec/controllers/super_admin/app_config_controller_spec.rb`
- Modify: `enterprise/app/controllers/api/v1/accounts/captain/llm_models_controller.rb`
- Modify: `enterprise/app/views/api/v1/accounts/captain/llm_models/index.json.jbuilder`
- Modify: `spec/enterprise/controllers/api/v1/accounts/captain/llm_models_controller_spec.rb`
- Modify: `enterprise/app/controllers/api/v1/accounts/captain/inboxes_controller.rb`
- Modify: `spec/enterprise/controllers/api/v1/accounts/captain/inboxes_controller_spec.rb`
- Modify: `enterprise/app/services/captain/payment_review/decision_service.rb`
- Modify: `spec/enterprise/services/captain/payment_review/decision_service_spec.rb`
- Modify: `app/services/chatwit/audio_transcription_service.rb`
- Create: `spec/services/chatwit/audio_transcription_service_spec.rb`

**Interfaces:**
- Consumes: Task 1 `operational_models`, `resolve_model!`, catalog source/status.
- Produces: validated Super Admin saves, validated phase-2 creation/runtime, and validated Captain Whisper runtime aliases.

- [ ] **Step 1: Add failing API/config validation specs**

Add these behaviors:

- Super Admin rejects a changed `CAPTAIN_WITDEV_MODEL` when `resolve_model!` raises and preserves the old InstallationConfig value.
- Super Admin transcription options include the recommended alias only if it exists in `operational_models`; no hardcoded alias is injected.
- `captain/llm_models` returns only `operational_models` plus exact `source` and `operational` fields.
- Captain inbox create returns 422 and creates no row for an unauthorized nonblank `phase2_model` on the WitDev route.
- Captain inbox create accepts a canonical phase-2 alias when `resolve_model!` succeeds.

The request expectation for the model endpoint is:

```ruby
expect(json_response).to include(source: 'litellm_proxy', operational: true)
expect(json_response.dig(:models, 0, :value)).to eq('witdev_claude/sonnet')
```

- [ ] **Step 2: Add failing phase-2 runtime and Whisper specs**

Update payment decision specs so the selected `phase2_model` is passed to `resolve_model!`, blank phase-2 model resolves the configured global alias, and catalog errors become `DecisionFailed` before `complete` is called.

Create `spec/services/chatwit/audio_transcription_service_spec.rb` with class-level examples:

```ruby
RSpec.describe Chatwit::AudioTranscriptionService do
  describe '.resolved_model' do
    it 'resolves the configured transcription alias through the canonical catalog' do
      allow(described_class).to receive(:model).and_return('witdev_antigravity/gemini-3.1-pro-low')
      expect(Chatwit::LlmProxy).to receive(:resolve_model!)
        .with('witdev_antigravity/gemini-3.1-pro-low')
        .and_return('witdev_antigravity/gemini-3.1-pro-low')

      expect(described_class.resolved_model).to eq('witdev_antigravity/gemini-3.1-pro-low')
    end
  end
end
```

- [ ] **Step 3: Run focused specs and verify RED**

```bash
eval "$(rbenv init -)"
POSTGRES_HOST=127.0.0.1 POSTGRES_PORT=5432 POSTGRES_USERNAME=postgres POSTGRES_PASSWORD=postgres \
REDIS_URL=redis://127.0.0.1:6379/0 bundle exec rspec \
spec/controllers/super_admin/app_config_controller_spec.rb \
spec/enterprise/controllers/api/v1/accounts/captain/llm_models_controller_spec.rb \
spec/enterprise/controllers/api/v1/accounts/captain/inboxes_controller_spec.rb \
spec/enterprise/services/captain/payment_review/decision_service_spec.rb \
spec/services/chatwit/audio_transcription_service_spec.rb
```

Expected: failures for missing authorization calls/status fields and `.resolved_model`.

- [ ] **Step 4: Restrict Super Admin options and saves**

Build both selects from `Chatwit::LlmProxy.operational_models`. Always call `apply_select_options` for both fields, including when the resulting hashes are empty, so an unavailable catalog renders an empty select instead of reverting to a free-text input. Replace the forced recommended merge with:

```ruby
def transcription_options(options)
  audio_options = options.select { |value, _label| Chatwit::AudioTranscriptionService.audio_capable?(value) }
  recommended = Chatwit::AudioTranscriptionService::RECOMMENDED_MODEL
  return audio_options unless audio_options.key?(recommended)

  { recommended => "#{audio_options.fetch(recommended)} (recommended)" }.merge(audio_options.except(recommended))
end
```

Before saving a changed `CAPTAIN_WITDEV_MODEL` or `CAPTAIN_WITDEV_TRANSCRIPTION_MODEL`, call `resolve_model!`. For transcription also enforce the existing audio transport guard. Catch catalog/model errors, add their messages to `errors`, skip that value, and redirect back with the alert. Do not validate unchanged fields submitted by the generic form.

Update the warning copy: the WitDev route is unavailable/fail-closed when required configuration is missing; it no longer claims Captain is using the legacy route.

- [ ] **Step 5: Validate phase-2 selection and execution**

In `LlmModelsController#index`:

```ruby
@models = Chatwit::LlmProxy.operational_models
@source = Chatwit::LlmProxy.catalog_source
@operational = Chatwit::LlmProxy.operational_catalog?
```

Expose `json.operational @operational` in Jbuilder.

In `InboxesController#create`, call `resolve_model!` for a present phase-2 alias only when `route_witdev?`; render 422 for catalog/model errors before saving.

In `DecisionService#model`:

```ruby
def model
  candidate = captain_inbox&.phase2_model.presence || Chatwit::LlmProxy.model
  return Chatwit::LlmProxy.resolve_model!(candidate) if Chatwit::LlmProxy.route_witdev?

  InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || LlmConstants::DEFAULT_MODEL
end
```

Use `route_witdev?` for the phase-2 API base/key so WitDev never falls through to the legacy key. Convert catalog/model errors to `DecisionFailed`.

- [ ] **Step 6: Validate Captain Whisper at runtime**

Add:

```ruby
def self.resolved_model
  Chatwit::LlmProxy.resolve_model!(model)
end
```

Memoize `resolved_model` per service instance, use it in the precondition and request body, and retain `audio_capable?` only as an additional transport safety check. An alias absent from the catalog must fail before the HTTP request.

- [ ] **Step 7: Run focused specs and verify GREEN**

Run the command from Step 3. Expected: all examples pass.

- [ ] **Step 8: Review checkpoint without commit**

```bash
git diff --check -- app/controllers/super_admin/app_configs_controller.rb \
enterprise/app/controllers/api/v1/accounts/captain enterprise/app/services/captain/payment_review/decision_service.rb \
app/services/chatwit/audio_transcription_service.rb spec/controllers/super_admin/app_config_controller_spec.rb \
spec/enterprise/controllers/api/v1/accounts/captain spec/enterprise/services/captain/payment_review/decision_service_spec.rb \
spec/services/chatwit/audio_transcription_service_spec.rb
```

Expected: no hardcoded recommended alias is injected into a select unless the central catalog contains it.

---

### Task 5: Surface canonical-catalog and invalid-selection state in Captain Settings

**Files:**
- Modify: `app/javascript/dashboard/store/captain/preferences.js`
- Modify: `app/javascript/dashboard/routes/dashboard/settings/captain/components/ModelDropdown.vue`
- Create: `app/javascript/dashboard/routes/dashboard/settings/captain/components/ModelDropdown.spec.js`
- Modify: `app/javascript/dashboard/i18n/locale/en/settings.json`

**Interfaces:**
- Consumes: Task 2 response `catalog` and feature `selection_valid`.
- Produces: `isCatalogOperational`, an unavailable disabled state, invalid-alias copy, and provider-icon fallback.

- [ ] **Step 1: Write failing component specs**

Create `ModelDropdown.spec.js` using `setActivePinia(createPinia())`, mock `vue-i18n` so `t(key) => key`, and mock `useAccount` with `isOnChatwootCloud: ref(false)`. Cover:

```javascript
store.catalog = { route: 'witdev', source: 'unavailable', operational: false };
store.features.editor = { models: [], selected: null, selection_valid: false };
expect(wrapper.get('button').attributes('disabled')).toBeDefined();
expect(wrapper.text()).toContain('CAPTAIN_SETTINGS.MODEL_CONFIG.CATALOG_UNAVAILABLE');
```

and:

```javascript
store.catalog = { route: 'witdev', source: 'litellm_proxy', operational: true };
store.features.editor = { models: [], selected: 'witdev/dead', selection_valid: false };
expect(wrapper.text()).toContain('witdev/dead');
expect(wrapper.text()).toContain('CAPTAIN_SETTINGS.MODEL_CONFIG.MODEL_UNAVAILABLE');
```

Also verify a model with an unknown provider renders the generic `i-lucide-bot` icon instead of an undefined icon.

- [ ] **Step 2: Run the component spec and verify RED**

```bash
pnpm test app/javascript/dashboard/routes/dashboard/settings/captain/components/ModelDropdown.spec.js --run
```

Expected: failures because catalog state and unavailable/invalid rendering do not exist.

- [ ] **Step 3: Store catalog state from both fetch and update**

In the Pinia store, add:

```javascript
catalog: { route: 'chatwoot', source: 'legacy', operational: true },
```

Assign `this.catalog = response.data.catalog || { route: 'chatwoot', source: 'legacy', operational: true }` in both actions. Add getters:

```javascript
isCatalogOperational: state =>
  state.catalog.route !== 'witdev' || state.catalog.operational === true,
isSelectionValidForFeature: state => featureKey =>
  state.features[featureKey]?.selection_valid !== false,
```

- [ ] **Step 4: Render fail-closed selection state**

In `ModelDropdown.vue`, compute the feature config, catalog state, and invalid selection. Disable the button when the WitDev catalog is non-operational. Display:

- `CATALOG_UNAVAILABLE` when disabled by catalog state;
- the persisted alias plus `MODEL_UNAVAILABLE` when `selection_valid === false`;
- the existing display name for a valid selection;
- the existing `SELECT_MODEL` copy otherwise.

Make `iconForModel` return `PROVIDER_ICONS[model.provider] || 'i-lucide-bot'`.

Add only these English keys under `CAPTAIN_SETTINGS.MODEL_CONFIG`:

```json
"CATALOG_UNAVAILABLE": "Canonical model catalog unavailable",
"MODEL_UNAVAILABLE": "Model unavailable — select another"
```

- [ ] **Step 5: Run Vitest and ESLint**

```bash
pnpm test app/javascript/dashboard/routes/dashboard/settings/captain/components/ModelDropdown.spec.js --run
pnpm eslint \
app/javascript/dashboard/store/captain/preferences.js \
app/javascript/dashboard/routes/dashboard/settings/captain/components/ModelDropdown.vue \
app/javascript/dashboard/routes/dashboard/settings/captain/components/ModelDropdown.spec.js
```

Expected: Vitest passes and ESLint exits 0.

- [ ] **Step 6: Review checkpoint without commit**

```bash
git diff --check -- app/javascript/dashboard/store/captain/preferences.js \
app/javascript/dashboard/routes/dashboard/settings/captain/components/ModelDropdown.vue \
app/javascript/dashboard/routes/dashboard/settings/captain/components/ModelDropdown.spec.js \
app/javascript/dashboard/i18n/locale/en/settings.json
```

Expected: only the Captain catalog state and two English strings changed.

---

### Task 6: Documentation and full focused verification

**Files:**
- Modify: `chatwitdocs/captain-witdev-llm-proxy.md`
- Include: `chatwitdocs/captain-witdev-canonical-models-design.md`

**Interfaces:**
- Consumes: completed behavior from Tasks 1–5.
- Produces: operator documentation and final evidence that WitDev is canonical and legacy is unchanged.

- [ ] **Step 1: Update the operational documentation**

Add sections to `chatwitdocs/captain-witdev-llm-proxy.md` documenting:

- global model and per-account precedence;
- which Captain feature maps to `editor`, `assistant`, `copilot`, and `label_suggestion`;
- exact `source == litellm_proxy` authorization rule;
- 422 behavior on invalid/unavailable alias;
- fail-closed runtime behavior and no legacy fallback when route is WitDev;
- how to replace an alias removed from the catalog;
- that embeddings, Files API, and native Whisper remain legacy.

Do not duplicate or modify the platform's model list in Chatwit docs.

- [ ] **Step 2: Run RuboCop on all touched Ruby files**

```bash
eval "$(rbenv init -)"
bundle exec rubocop \
lib/chatwit/llm_proxy.rb lib/chatwit/captain_model_resolver.rb \
app/models/concerns/captain_featurable.rb app/controllers/api/v1/accounts/captain/preferences_controller.rb \
lib/captain/base_task_service.rb lib/captain/reply_suggestion_service.rb lib/captain/label_suggestion_service.rb \
enterprise/lib/captain/conversation_completion_service.rb enterprise/app/models/concerns/agentable.rb \
enterprise/app/services/llm/base_ai_service.rb lib/llm/config.rb config/initializers/ai_agents.rb \
app/controllers/super_admin/app_configs_controller.rb \
enterprise/app/controllers/api/v1/accounts/captain/llm_models_controller.rb \
enterprise/app/controllers/api/v1/accounts/captain/inboxes_controller.rb \
enterprise/app/services/captain/payment_review/decision_service.rb app/services/chatwit/audio_transcription_service.rb
```

Expected: exit 0 with no offenses.

- [ ] **Step 3: Run the complete focused Ruby suite**

```bash
eval "$(rbenv init -)"
POSTGRES_HOST=127.0.0.1 POSTGRES_PORT=5432 POSTGRES_USERNAME=postgres POSTGRES_PASSWORD=postgres \
REDIS_URL=redis://127.0.0.1:6379/0 bundle exec rspec \
spec/lib/chatwit/llm_proxy_spec.rb spec/lib/chatwit/captain_model_resolver_spec.rb \
spec/models/concerns/captain_featurable_spec.rb \
spec/controllers/api/v1/accounts/captain/preferences_controller_spec.rb \
spec/lib/captain/base_task_service_spec.rb spec/lib/captain/rewrite_service_spec.rb \
spec/lib/captain/summary_service_spec.rb spec/lib/captain/follow_up_service_spec.rb \
spec/lib/captain/reply_suggestion_service_spec.rb spec/lib/captain/label_suggestion_service_spec.rb \
spec/enterprise/lib/captain/base_task_service_spec.rb \
spec/enterprise/lib/captain/conversation_completion_service_spec.rb \
spec/enterprise/models/concerns/agentable_spec.rb spec/enterprise/services/llm/base_ai_service_spec.rb \
spec/controllers/super_admin/app_config_controller_spec.rb \
spec/enterprise/controllers/api/v1/accounts/captain/llm_models_controller_spec.rb \
spec/enterprise/controllers/api/v1/accounts/captain/inboxes_controller_spec.rb \
spec/enterprise/services/captain/payment_review/decision_service_spec.rb \
spec/services/chatwit/audio_transcription_service_spec.rb
```

Expected: all examples pass with no unexpected warnings/errors.

- [ ] **Step 4: Run frontend verification**

```bash
pnpm test app/javascript/dashboard/routes/dashboard/settings/captain/components/ModelDropdown.spec.js --run
pnpm eslint \
app/javascript/dashboard/store/captain/preferences.js \
app/javascript/dashboard/routes/dashboard/settings/captain/components/ModelDropdown.vue \
app/javascript/dashboard/routes/dashboard/settings/captain/components/ModelDropdown.spec.js
```

Expected: Vitest passes and ESLint exits 0.

- [ ] **Step 5: Audit prohibited model sources and final diff**

```bash
rg -n "model/info|/v1/models|OMNIROUTE|config/llm.yml" \
lib/chatwit app/controllers/api/v1/accounts/captain enterprise/app/controllers/api/v1/accounts/captain \
app/javascript/dashboard/routes/dashboard/settings/captain
git diff --check
git status --short
git diff --stat
```

Expected: no new direct model-listing call outside `Chatwit::LlmProxy`, no whitespace errors, and only planned files are modified in the isolated worktree.

- [ ] **Step 6: Preserve the no-commit handoff**

Do not run `git commit` or `git push`. Report the worktree path, changed files, exact test/lint outcomes, and any residual validation risk to the user.
