# Interactive templates and payment favorites design

## Goal

Let agents edit or delete saved WhatsApp interactive-message templates directly from the saved-template cards, and preserve the selected interactive CTA in each saved InfinitePay payment favorite.

## Chosen approach

Reuse `InteractiveMessageCreator.vue` as the sole form for both creation and editing. `TemplatesPicker.vue` owns the cards and emits an edit event; `Modal.vue` owns the selected record and switches to the creator with that record as a read-only prop. The creator copies the record into its local form state, including `header_image_url`, and emits completion when the existing record is updated.

The update API rebuilds `payload` with `Whatsapp::InteractiveTemplatePayloadBuilder`, exactly as creation does. This prevents stale WhatsApp payloads when any editable field changes. Deleting remains scoped to the account and removes the template from the Vuex store.

Payment presets receive an optional `whatsapp_interactive_template_id`. Saving a favorite writes that field; selecting it restores the stored ID into the payment modal, so the next payment-link request uses the same CTA. The foreign key is nullable and uses `on_delete: :nullify`, so deleting a template does not break an existing favorite.

## Boundaries and data flow

- `TemplatesPicker.vue`: renders saved cards and emits `onEditInteractive`; it does not own edit-form state.
- `Modal.vue`: maps the edit event to `editingInteractiveTemplate`, passes it down as `template`, and returns to the picker after saving.
- `InteractiveMessageCreator.vue`: validates and submits either `create` or `update`; image handling continues through its existing publishing path.
- Vuex/API: expose `update` and replace the updated record in the store.
- Rails controller/model/migration: accept and persist only the scoped, validated attributes.
- Payment modal: derives the CTA selection from a chosen preset and includes it when it creates a preset.

## UX and error handling

The card body continues to send the template. Small edit and delete icon buttons stop event propagation, so their actions cannot accidentally send a message. Existing alert patterns report failed saves, updates, and deletions. If a saved preset refers to a template that was deleted, its selected CTA becomes empty and the payment link still sends normally.

## Validation

Request specs prove template updates rebuild and return the changed record, and payment-preset creation persists the optional CTA reference. Focused Vuex tests cover replacing an updated template; lint covers the modified Vue files.
