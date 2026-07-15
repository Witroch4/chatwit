# Interactive Templates and Payment Favorites Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow saved WhatsApp interactive templates to be edited and deleted from their cards, and make InfinitePay favorites restore their selected interactive CTA.

**Architecture:** The existing interactive-message creator becomes an edit-capable form, while the picker and modal retain orchestration. Rails adds an account-scoped update action and an optional payment-preset foreign key. The Vuex stores remain the client source of truth after API responses.

**Tech Stack:** Rails 7, Active Record, RSpec, Vue 3, Vuex, Axios, Vitest, Tailwind utility classes.

## Global Constraints

- Preserve the existing dashboard visual language and keep all user-facing copy in `en` and `pt_BR` locale files.
- Rebuild interactive WhatsApp payloads through `Whatsapp::InteractiveTemplatePayloadBuilder` on both create and update.
- Keep the payment-preset CTA reference optional and nullify it if the referenced template is deleted.
- Do not deploy or push; merge the validated commit into the repository integration branch only.

---

### Task 1: Persist a CTA selection with payment presets

**Files:**
- Create: `db/migrate/20260715000000_add_whatsapp_interactive_template_to_payment_presets.rb`
- Modify: `app/models/payment_preset.rb`
- Modify: `app/controllers/api/v1/accounts/payment_presets_controller.rb`
- Test: `spec/models/payment_preset_spec.rb`

**Interfaces:**
- Consumes: `PaymentPreset#whatsapp_interactive_template_id`, optional account-scoped template ID.
- Produces: JSON preset records that include the selected CTA ID.

- [ ] **Step 1: Write the failing model test**

```ruby
it 'allows a preset to reference an interactive template from its account' do
  preset = create(:payment_preset, account: account, whatsapp_interactive_template: template)

  expect(preset.whatsapp_interactive_template).to eq(template)
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `eval "$(rbenv init -)" && bundle exec rspec spec/models/payment_preset_spec.rb`

Expected: failure because `PaymentPreset` has no interactive-template association.

- [ ] **Step 3: Write the minimal implementation**

```ruby
belongs_to :whatsapp_interactive_template, optional: true
```

Add a nullable reference with `foreign_key: { on_delete: :nullify }`, then permit `:whatsapp_interactive_template_id` in the payment-presets controller.

- [ ] **Step 4: Run the test to verify it passes**

Run: `eval "$(rbenv init -)" && bundle exec rspec spec/models/payment_preset_spec.rb`

Expected: PASS.

### Task 2: Update interactive templates through the existing creator

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/api/v1/accounts/whatsapp_interactive_templates_controller.rb`
- Modify: `app/policies/whatsapp_interactive_template_policy.rb`
- Modify: `app/javascript/dashboard/api/whatsappInteractiveTemplates.js`
- Modify: `app/javascript/dashboard/store/modules/whatsappInteractiveTemplates.js`
- Modify: `app/javascript/dashboard/components/widgets/conversation/WhatsappTemplates/TemplatesPicker.vue`
- Modify: `app/javascript/dashboard/components/widgets/conversation/WhatsappTemplates/Modal.vue`
- Modify: `app/javascript/dashboard/components/widgets/conversation/WhatsappTemplates/InteractiveMessageCreator.vue`
- Test: `spec/requests/api/v1/accounts/whatsapp_interactive_templates_spec.rb`
- Test: `app/javascript/dashboard/store/modules/specs/whatsappInteractiveTemplates.spec.js`

**Interfaces:**
- Consumes: `PATCH /api/v1/accounts/:account_id/whatsapp_interactive_templates/:id` with `whatsapp_interactive_template` attributes.
- Produces: the rebuilt and updated record; `onEditInteractive(template)` from picker to modal; `template` prop to creator.

- [ ] **Step 1: Write failing API and store tests**

```ruby
patch api_v1_account_whatsapp_interactive_template_path(account, template), params: {
  whatsapp_interactive_template: { body_text: 'Texto atualizado' }
}

expect(response).to have_http_status(:ok)
expect(template.reload.body_text).to eq('Texto atualizado')
```

```javascript
expect(mutations[types.UPDATE_WHATSAPP_INTERACTIVE_TEMPLATE](state, updated).records)
  .toEqual([updated]);
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `eval "$(rbenv init -)" && bundle exec rspec spec/requests/api/v1/accounts/whatsapp_interactive_templates_spec.rb` and `pnpm test app/javascript/dashboard/store/modules/specs/whatsappInteractiveTemplates.spec.js`

Expected: route/action/mutation failures because update support does not exist.

- [ ] **Step 3: Write the minimal implementation**

Add the `update` route, authorization policy, controller action that rebuilds `payload`, and Vuex API/action/mutation. Make saved-card edit/delete buttons stop propagation. Hydrate and submit the existing creator in edit mode, including the existing `header_image_url`.

- [ ] **Step 4: Run tests to verify they pass**

Run: the same RSpec and Vitest commands.

Expected: PASS.

### Task 3: Restore the CTA when a payment favorite is selected

**Files:**
- Modify: `app/javascript/dashboard/components/widgets/conversation/PaymentLink/Modal.vue`
- Test: `app/javascript/dashboard/components/widgets/conversation/PaymentLink/Modal.spec.js`

**Interfaces:**
- Consumes: a preset with optional `whatsapp_interactive_template_id`.
- Produces: a selected CTA ID in both the create-preset payload and payment-link request.

- [ ] **Step 1: Write the failing component test**

```javascript
await wrapper.vm.selectPreset({
  id: 1,
  amount_cents: 27000,
  description: 'Lote',
  whatsapp_interactive_template_id: 12,
});

expect(wrapper.vm.selectedInteractiveTemplateId).toBe(12);
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pnpm test app/javascript/dashboard/components/widgets/conversation/PaymentLink/Modal.spec.js`

Expected: failure because selecting a preset does not restore its CTA.

- [ ] **Step 3: Write the minimal implementation**

Set `selectedInteractiveTemplateId` from the selected preset and include it in the `payment_preset` payload created by `onSend`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `pnpm test app/javascript/dashboard/components/widgets/conversation/PaymentLink/Modal.spec.js`

Expected: PASS.

### Task 4: Localize, document, and verify

**Files:**
- Modify: `app/javascript/dashboard/i18n/locale/en/whatsappTemplates.json`
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/whatsappTemplates.json`
- Create: `chatwitdocs/interactive-templates-payment-favorites.md`

- [ ] **Step 1: Add edit-mode and card-action translations**

Use the existing `WHATSAPP_TEMPLATES.INTERACTIVE` namespace for the editor heading, save action, and accessible labels.

- [ ] **Step 2: Run focused verification**

Run: `pnpm eslint <modified Vue and JS files>` and `eval "$(rbenv init -)" && bundle exec rubocop <modified Ruby files>`.

Expected: exit code 0.

- [ ] **Step 3: Commit and integrate**

Run: `git add <only task files> && git commit -m "feat(whatsapp): manage interactive template favorites"`, then merge the feature branch into the repository's integration branch. Do not push or deploy.
