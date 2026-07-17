json.payload do
  json.array! @captain_inboxes do |captain_inbox|
    json.partial! 'api/v1/models/inbox', formats: [:json], resource: captain_inbox.inbox
    json.captain_mode captain_inbox.mode
    json.phase2_model captain_inbox.phase2_model
    json.phase2_prompt captain_inbox.phase2_prompt
    json.phase2_payment_preset_ids captain_inbox.phase2_payment_preset_ids
    json.default_prompt Captain::PaymentReview::DEFAULT_PROMPT
  end
end

json.meta do
  json.total_count @captain_inboxes.count
  json.page 1
end
