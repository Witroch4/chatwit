# Canned Response Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a desktop composer button that opens a selectable, reorderable canned-response modal and persists one account-wide order.

**Architecture:** The backend adds a `position` column and an account-scoped collection reorder endpoint. The existing canned-response store/API reads and writes that ordered list. A focused modal component uses the existing `vuedraggable` dependency for an explicit organize mode, while `ReplyBox` sends a selection into the Woot writer's current `cannedResponse` insertion implementation.

**Tech Stack:** Rails 7.1, Vue 3 Composition API, Vuex, `vuedraggable` 4.1.0, Tailwind utilities, existing `woot-modal` and dashboard i18n.

## Global Constraints

- Work only in `/home/wital/chatwit/.claude/worktrees/canned-response-picker` on `feat/canned-response-picker`.
- The feature is desktop-only; do not change `components-next/mobile/` or mobile locale files.
- Reuse `vuedraggable`; do not add a dependency.
- Keep all new user-facing strings in `en` and `pt_BR` dashboard locale bundles.
- Use the editor's existing `insertSpecialContent('cannedResponse', content)` behavior; do not duplicate rich-text or variable replacement logic.
- The account owns the saved order, so every agent in the account receives the same ordered list.
- Repository guidance says not to add specs unless explicitly requested. Do not add new test files; use targeted linting, migration checks, and manual/API validation instead.
- Add an implementation note under `chatwitdocs/`.

---

### Task 1: Persist and return an account-wide canned-response order

**Files:**
- Create: `db/migrate/20260715000000_add_position_to_canned_responses.rb`
- Modify: `app/models/canned_response.rb`
- Modify: `app/controllers/api/v1/accounts/canned_responses_controller.rb`
- Modify: `config/routes.rb:115`

**Interfaces:**
- Produces `CannedResponse.ordered`, which sorts by `position` then `id`.
- Produces `POST /api/v1/accounts/:account_id/canned_responses/reorder`, accepting `{ canned_response_ids: number[] }` and returning the full ordered account collection.
- Consumes `Current.account`; no supplied id may select a response from another account.

- [ ] **Step 1: Add an ordered position column and deterministic backfill**

Create the migration below. A nullable creation avoids a temporary default that would incorrectly place later records at zero. Existing records receive positions per account ordered by their historical creation time and id; the composite index supports the account list query.

```ruby
class AddPositionToCannedResponses < ActiveRecord::Migration[7.1]
  def up
    add_column :canned_responses, :position, :integer

    execute <<~SQL.squish
      UPDATE canned_responses
      SET position = ordered.position
      FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY account_id ORDER BY created_at, id) AS position
        FROM canned_responses
      ) AS ordered
      WHERE canned_responses.id = ordered.id
    SQL

    change_column_null :canned_responses, :position, false
    add_index :canned_responses, [:account_id, :position]
  end

  def down
    remove_index :canned_responses, column: [:account_id, :position]
    remove_column :canned_responses, :position
  end
end
```

- [ ] **Step 2: Make new records append and expose the ordered scope**

In `CannedResponse`, add the scope and lifecycle callback below before the existing search scope. `position` is assigned only for new records and therefore explicit positions from migrations or reordering remain intact.

```ruby
before_validation :assign_position, on: :create

scope :ordered, -> { order(:position, :id) }

private

def assign_position
  self.position = account.canned_responses.maximum(:position).to_i + 1 if position.nil?
end
```

- [ ] **Step 3: Add a protected collection reorder route and controller action**

Change the canned-response resource route to a block with `post :reorder, on: :collection`. In the controller, add `reorder` and its two helpers. The action rejects missing, duplicate, incomplete, or cross-account id arrays before changing data. It updates all positions within a transaction and returns `canned_responses`, so the client can replace its local cache with the authoritative order.

```ruby
def reorder
  ordered_ids = reorder_params[:canned_response_ids]
  account_ids = Current.account.canned_responses.pluck(:id)

  unless valid_reorder?(ordered_ids, account_ids)
    return render json: { error: 'Invalid canned response order' }, status: :unprocessable_entity
  end

  CannedResponse.transaction do
    ordered_ids.each_with_index do |id, index|
      Current.account.canned_responses.where(id: id).update_all(position: index + 1)
    end
  end

  render json: canned_responses
end

def reorder_params
  params.permit(canned_response_ids: [])
end

def valid_reorder?(ordered_ids, account_ids)
  return false unless ordered_ids.is_a?(Array)

  normalized_ids = ordered_ids.map(&:to_i)
  normalized_ids.size == account_ids.size &&
    normalized_ids.uniq.size == normalized_ids.size &&
    normalized_ids.sort == account_ids.sort
end
```

Update the no-search branch of `canned_responses` to `Current.account.canned_responses.ordered`. Keep the existing relevance ordering for a search, appending `.order(:position, :id)` only as a tie breaker after `order_by_search`.

- [ ] **Step 4: Validate the Rails change without adding specs**

Run the targeted migration and lint checks after initializing rbenv. Confirm the migration applies in the local development database, then use a signed-in request or Rails console to verify that an incomplete id list returns HTTP 422 and a complete account list returns records in the submitted order.

```bash
eval "$(rbenv init -)"
bundle exec rubocop app/models/canned_response.rb app/controllers/api/v1/accounts/canned_responses_controller.rb db/migrate/20260715000000_add_position_to_canned_responses.rb
bundle exec rails db:migrate
```

- [ ] **Step 5: Commit the persistence layer**

```bash
git add db/migrate/20260715000000_add_position_to_canned_responses.rb app/models/canned_response.rb app/controllers/api/v1/accounts/canned_responses_controller.rb config/routes.rb
git commit -m "feat(canned-responses): persist account response order"
```

### Task 2: Expose response reordering through the existing frontend store

**Files:**
- Modify: `app/javascript/dashboard/api/cannedResponse.js`
- Modify: `app/javascript/dashboard/store/modules/cannedResponse.js`

**Interfaces:**
- Produces `CannedResponseAPI.reorder(cannedResponseIds)`.
- Produces Vuex action `reorderCannedResponses(_, cannedResponseIds)`, resolving to the ordered server responses.
- Consumed by `CannedResponsePickerModal.vue` in Task 3.

- [ ] **Step 1: Add the API client method**

Add this method beside `get`, retaining `ApiClient`'s account-scoped base URL.

```javascript
reorder(cannedResponseIds) {
  return axios.post(`${this.url}/reorder`, {
    canned_response_ids: cannedResponseIds,
  });
}
```

- [ ] **Step 2: Add a Vuex action that replaces records with the server order**

Add `reorderCannedResponses` to `actions`. It uses the existing `SET_CANNED` mutation rather than manually moving Vuex records, ensuring a failed request cannot leave local state in a false order.

```javascript
reorderCannedResponses: async function reorderCannedResponses(
  { commit },
  cannedResponseIds
) {
  const response = await CannedResponseAPI.reorder(cannedResponseIds);
  commit(types.default.SET_CANNED, response.data);
  return response.data;
},
```

- [ ] **Step 3: Run focused frontend linting**

```bash
pnpm eslint app/javascript/dashboard/api/cannedResponse.js app/javascript/dashboard/store/modules/cannedResponse.js
```

- [ ] **Step 4: Commit the frontend data layer**

```bash
git add app/javascript/dashboard/api/cannedResponse.js app/javascript/dashboard/store/modules/cannedResponse.js
git commit -m "feat(canned-responses): add reorder store action"
```

### Task 3: Build the selectable and reorderable canned-response modal

**Files:**
- Create: `app/javascript/dashboard/components/widgets/conversation/CannedResponsePickerModal.vue`
- Modify: `app/javascript/dashboard/i18n/locale/en/conversation.json`
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/conversation.json`

**Interfaces:**
- Consumes `getCannedResponses`, `getUIFlags`, `getCannedResponse`, and `reorderCannedResponses` from the existing Vuex module.
- Emits `select(content)` when an agent selects a response in normal mode and `close` when dismissed.
- Consumed by `ReplyBox.vue` in Task 4.

- [ ] **Step 1: Create a focused Composition API modal content component**

Use `<script setup>`, `Draggable` from `vuedraggable`, `useStore`, `useMapGetter`, `useI18n`, `useAlert`, and `useMessageFormatter`. On mount, dispatch `getCannedResponse`. Mirror store responses into a `localResponses` ref with a shallow watch so `v-model` is only local while dragging. Define `isOrganizing`, `isSavingOrder`, and `isLoading` as explicit derived/local state.

The selection handler must do nothing in organize mode and otherwise emit the raw `response.content`. The drag-end handler must dispatch the full ordered id list, turn organize mode off on success, and on failure re-fetch records then display `CONVERSATION.REPLYBOX.CANNED_RESPONSES.REORDER_ERROR`.

```javascript
const selectResponse = response => {
  if (!isOrganizing.value) emit('select', response.content);
};

const saveOrder = async () => {
  isSavingOrder.value = true;
  try {
    await store.dispatch(
      'reorderCannedResponses',
      localResponses.value.map(({ id }) => id)
    );
    isOrganizing.value = false;
  } catch {
    await store.dispatch('getCannedResponse');
    useAlert(t('CONVERSATION.REPLYBOX.CANNED_RESPONSES.REORDER_ERROR'));
  } finally {
    isSavingOrder.value = false;
  }
};
```

Render `woot-modal-header`, an outline organize/done button, and a scrollable `Draggable` list. Each normal row is a button displaying `/short_code` plus `getPlainText(content)` with `line-clamp-2`; in organize mode it shows a `i-lucide-grip-vertical` handle and does not select. Use `item-key="id"`, `handle=".canned-response-drag-handle"`, and a Tailwind `ghost-class` such as `opacity-50`—no scoped or custom stylesheet. Include a localized empty state and a loading indicator.

- [ ] **Step 2: Add localized desktop copy**

Add `CONVERSATION.REPLYBOX.CANNED_RESPONSES` in both locale files with the following keys:

```json
{
  "BUTTON_TOOLTIP": "Open canned responses",
  "TITLE": "Canned responses",
  "DESCRIPTION": "Choose a saved response to insert into this message.",
  "ORGANIZE": "Organize",
  "DONE": "Done",
  "EMPTY": "No canned responses are available.",
  "REORDER_ERROR": "Could not save the canned response order. Please try again."
}
```

Translate each value naturally into Brazilian Portuguese in `pt_BR/conversation.json` (for example, `Abrir respostas prontas`, `Respostas prontas`, and `Organizar`).

- [ ] **Step 3: Run focused Vue linting**

```bash
pnpm eslint app/javascript/dashboard/components/widgets/conversation/CannedResponsePickerModal.vue app/javascript/dashboard/i18n/locale/en/conversation.json app/javascript/dashboard/i18n/locale/pt_BR/conversation.json
```

- [ ] **Step 4: Commit the picker UI**

```bash
git add app/javascript/dashboard/components/widgets/conversation/CannedResponsePickerModal.vue app/javascript/dashboard/i18n/locale/en/conversation.json app/javascript/dashboard/i18n/locale/pt_BR/conversation.json
git commit -m "feat(canned-responses): add reorderable picker modal"
```

### Task 4: Connect the first composer action to exact slash-command insertion

**Files:**
- Modify: `app/javascript/dashboard/components/widgets/WootWriter/Editor.vue`
- Modify: `app/javascript/dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue`
- Modify: `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue`

**Interfaces:**
- `WootMessageEditor` publicly exposes `insertCannedResponse(content)`.
- `ReplyBottomPanel` receives `toggleCannedResponsePicker` and renders its action before emoji.
- `ReplyBox` opens `CannedResponsePickerModal` and calls `messageEditor.insertCannedResponse(content)` on selection.

- [ ] **Step 1: Expose a narrow writer method that reuses the slash insertion path**

In `Editor.vue`, add the method below after `insertSpecialContent`, then expose it alongside `focusEditorInputField`. Focusing first provides the current editor selection and lets the existing `getContentNode`/`insertSpecialContent` logic preserve variable expansion, rich formatting, scrolling, and canned-response analytics.

```javascript
function insertCannedResponse(content) {
  focusEditorInputField();
  insertSpecialContent('cannedResponse', content);
}

defineExpose({ focusEditorInputField, insertCannedResponse });
```

- [ ] **Step 2: Add the action before the emoji button**

In `ReplyBottomPanel.vue`, add a `toggleCannedResponsePicker` function prop. Make the new `NextButton` the first element inside `.left-wrap`, immediately before the existing emoji `NextButton`. It must have `v-if="!isEditorDisabled && !isOnPrivateNote"`, use `icon="i-lucide-messages-square"`, `slate`, `faded`, and `sm`, obtain its tooltip from `CONVERSATION.REPLYBOX.CANNED_RESPONSES.BUTTON_TOOLTIP`, and call `toggleCannedResponsePicker`.

- [ ] **Step 3: Own modal state and selection bridge in ReplyBox**

Import `CannedResponsePickerModal`. Add `showCannedResponsePicker: false` to `data`, a `toggleCannedResponsePicker` method that flips it, and a `selectCannedResponse(content)` method that closes the modal and on the next tick invokes `this.messageEditor?.insertCannedResponse(content)`.

Pass `:toggle-canned-response-picker="toggleCannedResponsePicker"` to `ReplyBottomPanel`. Render the modal beside the existing templates modals:

```vue
<woot-modal
  v-model:show="showCannedResponsePicker"
  :on-close="() => (showCannedResponsePicker = false)"
>
  <CannedResponsePickerModal
    v-if="showCannedResponsePicker"
    @close="showCannedResponsePicker = false"
    @select="selectCannedResponse"
  />
</woot-modal>
```

- [ ] **Step 4: Validate the complete desktop interaction**

Run focused linting, start the local dashboard, and manually verify all of the following with at least two canned responses: the new action is the first button before emoji; the modal shows shortcuts and message starts; selecting a response inserts the same rendered content as `/shortcut`; entering organize mode prevents selection; dragging and closing/reopening preserves the order; reloading keeps it; and the slash menu receives the same default order. Verify private notes do not show the button and the mobile layout has no changed files.

```bash
pnpm eslint app/javascript/dashboard/components/widgets/WootWriter/Editor.vue app/javascript/dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue app/javascript/dashboard/components/widgets/conversation/CannedResponsePickerModal.vue
git diff --check
```

- [ ] **Step 5: Commit the composer integration**

```bash
git add app/javascript/dashboard/components/widgets/WootWriter/Editor.vue app/javascript/dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue
git commit -m "feat(canned-responses): add composer picker button"
```

### Task 5: Document the Chatwit-only behavior and finish validation

**Files:**
- Create: `chatwitdocs/canned-response-picker.md`
- Modify: `docs/superpowers/specs/2026-07-15-canned-response-picker-design.md`

**Interfaces:**
- Documents the desktop composer entry point, account-scoped persistence, and reuse of the slash-command insertion mechanism.

- [ ] **Step 1: Write the implementation note**

Create `chatwitdocs/canned-response-picker.md` with: the user-visible behavior; the desktop-only scope; the `vuedraggable` dependency already bundled by Chatwit; the `position` column and reorder endpoint; the fact that insertion delegates to `WootWriter/Editor.vue#insertSpecialContent('cannedResponse', content)`; and the focused manual validation checklist from Task 4.

- [ ] **Step 2: Mark the approved design as implemented**

Append an `## Implementation` section to the design document naming the completed migration, endpoint, component, and validation commands. Do not alter the approved requirements.

- [ ] **Step 3: Run final focused verification**

```bash
pnpm eslint app/javascript/dashboard/api/cannedResponse.js app/javascript/dashboard/store/modules/cannedResponse.js app/javascript/dashboard/components/widgets/WootWriter/Editor.vue app/javascript/dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue app/javascript/dashboard/components/widgets/conversation/CannedResponsePickerModal.vue
eval "$(rbenv init -)"
bundle exec rubocop app/models/canned_response.rb app/controllers/api/v1/accounts/canned_responses_controller.rb db/migrate/20260715000000_add_position_to_canned_responses.rb
git diff --check
git status --short
```

- [ ] **Step 4: Commit documentation**

```bash
git add chatwitdocs/canned-response-picker.md docs/superpowers/specs/2026-07-15-canned-response-picker-design.md
git commit -m "docs(canned-responses): document picker ordering"
```

## Plan Self-Review

- **Spec coverage:** Tasks 1 and 2 persist and retrieve account order; Task 3 presents selectable/reorderable previews; Task 4 places the button first and reuses the `/` insertion path; Task 5 documents the fork-only behavior.
- **Placeholder scan:** No unfinished markers, deferred implementation, or unspecified error handling remains.
- **Type consistency:** The backend accepts `canned_response_ids`; API, Vuex, picker, and controller use the same name. The picker emits `select(content)`, and `ReplyBox` invokes `insertCannedResponse(content)` exposed by the editor.
