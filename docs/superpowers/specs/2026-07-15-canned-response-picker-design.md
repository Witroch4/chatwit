# Canned Response Picker Design

## Goal

Let agents insert a canned response from a dedicated composer button, while allowing each account to define one shared drag-and-drop order for that list.

## Scope

- Add the first composer action, immediately before the emoji action, in the desktop reply box.
- Open a modal that lists the account's canned responses with the shortcut and a plain-text preview of the beginning of the message.
- Selecting a response must call the rich editor's existing `cannedResponse` insertion path, which is also used when an agent types `/shortcut`.
- Provide an explicit organize mode in the modal. In this mode, drag handles reorder rows through the already-installed `vuedraggable` package.
- Persist the resulting order for every agent in the current account.
- Keep the slash-command menu unchanged and have it read the same persisted order.

## Exclusions

- No new dependency: Chatwit already includes `vuedraggable` 4.1.0 and uses it elsewhere.
- No change to canned-response creation, editing, deletion, or permissions.
- No mobile/PWA change. The supplied composer UI maps to the desktop `ReplyBox` action bar.
- No user-specific ordering. The order belongs to the account because canned responses themselves are account-scoped.

## Architecture

`ReplyBottomPanel` will expose a `toggleCannedResponsePicker` callback and render its new action before the emoji button. `ReplyBox` owns the open state, renders a focused picker modal, and forwards a selected response into `WootMessageEditor` through a small public editor method. That method will reuse `insertSpecialContent('cannedResponse', content)`, preserving variable handling, rich-text compatibility, editor focus, and existing analytics.

The picker component will fetch through the existing Vuex canned-response store, keep a local ordered list for drag interactions, and emit either `select(content)` or `reorder(ids)`. Its normal rows are selectable; organize mode makes the drag handle available and prevents accidental insertion while sorting. Each row shows `/short_code` plus a truncated plain-text preview.

The Rails model will receive a non-null `position` column. Existing rows will be deterministically backfilled by creation time and id. The index endpoint will return records ordered by `position`, with an id fallback. A collection `POST /canned_responses/reorder` endpoint will accept the complete ordered id list, verify all ids belong to `Current.account`, then update positions in one transaction. The client will update its store only after that request succeeds; on error it will reload the server order and show an alert.

## Data Flow

```text
Composer button
  -> ReplyBox opens CannedResponsePickerModal
  -> Vuex getCannedResponse / GET canned_responses (position order)
  -> click row -> ReplyBox -> WootMessageEditor.insertCannedResponse()
  -> existing insertSpecialContent('cannedResponse', content)

Organize mode
  -> vuedraggable changes local rows
  -> POST canned_responses/reorder { canned_response_ids: [...] }
  -> transaction saves position 1..n for this account
  -> Vuex records receive the ordered response list
```

## Component Boundaries

| Unit | Responsibility | Contract |
| --- | --- | --- |
| `CannedResponsePickerModal.vue` | Fetch, display, search, select, and reorder canned responses. | Emits `select(content)` and `close`; dispatches the reorder store action. |
| `ReplyBottomPanel.vue` | Render the first composer action. | Receives `toggleCannedResponsePicker` function. |
| `ReplyBox.vue` | Own visual modal state and bridge a selection to the editor. | Calls editor's `insertCannedResponse(content)` method. |
| `WootWriter/Editor.vue` | Expose the existing safe canned-response insertion behavior. | Public `insertCannedResponse(content)` method delegates to `insertSpecialContent`. |
| canned-response store/API | Persist and expose ordered records. | `reorderCannedResponses(ids)` posts an ordered id array. |
| `CannedResponsesController` | Authorize and atomically persist account order. | `reorder` rejects lists that do not exactly match the account's records. |

## Error Handling and Accessibility

- The picker shows the existing loading/empty state conventions and closes only after a successful selection.
- Reorder failures retain no optimistic server state: reload the list and show a localized error alert.
- Buttons have localized labels/tooltips, Escape/overlay use the established `woot-modal` behavior, and drag controls use an explicit organize mode with a visible handle.
- New user-facing copy is added to the English and Brazilian Portuguese locale bundles used by the desktop composer.

## Validation

The repository instruction asks not to add specs unless explicitly requested. Validation will therefore use focused frontend linting, Ruby linting, schema/migration checks, and an authenticated manual/API check of selection and persisted ordering.

## Documentation

`chatwitdocs/` will receive a concise implementation note describing the desktop-only picker, reused slash-command insertion path, account-scoped order, and the new reorder endpoint.
