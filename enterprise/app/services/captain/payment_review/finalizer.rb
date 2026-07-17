# Atomic local terminal for a phase-2 run (spec §9.5/§14, Emenda E4).
#
# Every terminal happens in one conversation-locked transaction guarded by the
# lease token: optional idempotent message + run terminal + trigger consumption
# + canonical label release (only when the present generation is the claimed
# one). External HTTP (preset charge creation) always happens BEFORE the lock.
class Captain::PaymentReview::Finalizer
  class StaleRunError < StandardError; end
  class EnvelopeExpiredError < StandardError; end
  class PresetNotAllowedError < StandardError; end

  CANONICAL_LABEL = Captain::PaymentReviewTrigger::CANONICAL_LABEL
  ENVELOPE_OUTCOMES = {
    'send_cta' => :cta_accepted,
    'send_pix_key' => :pix_key_accepted,
    'send_status' => :status_accepted
  }.freeze

  def initialize(run:, token:)
    @run = run
    @token = token
  end

  def paid!
    finalize!(outcome: :paid, reason_code: 'provider_confirmed')
    enqueue_verified_reconciliation
  end

  def no_action! = finalize!(outcome: :no_action)

  def reply!(decision)
    finalize!(
      outcome: :replied,
      action: 'reply',
      reason_code: decision.reason_code,
      message_params: { content: decision.response }
    )
  end

  def complete_with_envelope!(decision, envelope)
    raise EnvelopeExpiredError, 'envelope is not authorized' unless envelope.authorized?
    raise EnvelopeExpiredError, 'envelope expired' if envelope.expired?

    finalize!(
      outcome: ENVELOPE_OUTCOMES.fetch(decision.action),
      action: decision.action,
      reason_code: decision.reason_code,
      message_params: envelope_message_params(envelope),
      envelope: envelope
    )
  end

  # Deterministic pix message from the operator-configured key (never the LLM).
  def send_pix_key!(decision, pix_key)
    finalize!(
      outcome: :pix_key_accepted,
      action: 'send_pix_key',
      reason_code: decision.reason_code,
      message_params: { content: I18n.t('conversations.captain.pix_key_message', pix_key: pix_key) }
    )
  end

  def send_payment_preset!(decision)
    preset = authorized_preset!(decision)
    charge = generate_charge(preset)
    finalize!(
      outcome: :payment_preset_accepted,
      action: 'send_payment_preset',
      reason_code: decision.reason_code,
      message_params: charge_message_params(charge)
    )
  end

  def handoff!(decision)
    with_owned_run do |conversation|
      create_private_note(conversation, reason: decision.reason_code)
      @run.update!(
        status: :completed, outcome: :handoff_required, decision_action: 'handoff_required',
        reason_code: decision.reason_code, completed_at: Time.current
      )
      conversation.bot_handoff!
    end
  end

  def fail!(reason_code:, error_message: nil)
    with_owned_run do |conversation|
      create_private_note(conversation, reason: reason_code)
      @run.update!(
        status: :failed, error_code: reason_code,
        error_message: error_message.to_s.first(255).presence, completed_at: Time.current
      )
    end
    promote_successor
  end

  private

  def finalize!(outcome:, action: nil, reason_code: nil, message_params: nil, envelope: nil)
    message = nil
    with_owned_run do |conversation|
      raise EnvelopeExpiredError, 'envelope expired' if envelope&.expired?

      message = create_idempotent_message(conversation, action, message_params) if message_params
      @run.update!(
        status: :completed, outcome: outcome, decision_action: action,
        reason_code: reason_code, response_message_id: message&.id, completed_at: Time.current
      )
      consume_trigger_and_release_label(conversation)
    end
    promote_successor
    message
  end

  def with_owned_run
    conversation = @run.conversation.class.find(@run.conversation_id)
    result = nil
    conversation.with_lock do
      @run.reload
      raise StaleRunError, 'run is no longer owned by this worker' unless @run.lease_held_by?(@token)

      result = yield(conversation)
    end
    result
  end

  def create_idempotent_message(conversation, action, message_params)
    params = message_params.merge(
      message_type: 'outgoing',
      idempotency_key: "captain-payment-review:#{@run.id}:#{action}"
    ).compact
    Current.executed_by = assistant
    Messages::IdempotentCreateService.new(user: assistant, conversation: conversation, params: params).perform
  ensure
    Current.executed_by = nil
  end

  def assistant
    @run.captain_assistant || @run.conversation.inbox.captain_inbox&.captain_assistant
  end

  def consume_trigger_and_release_label(conversation)
    claimed = @run.trigger
    claimed.update!(state: :consumed, deactivated_at: Time.current) if claimed.present? && claimed.deactivated_at.nil?

    present = conversation.captain_payment_review_triggers
                          .for_canonical_label
                          .present_generation
                          .first
    return if present.present? && present.id != claimed&.id

    Captain::PaymentReview::LabelMutationService.new(
      conversation: conversation, labels: [CANONICAL_LABEL], source: :system
    ).remove!
  end

  def promote_successor
    Captain::PaymentReview::WakeService.new(@run.conversation).call
  end

  # Captain polling and the verified webhook share the same reconciler
  # (spec §11.3): a paid outcome enqueues the verification worker, never
  # mutating local payment state directly.
  def enqueue_verified_reconciliation
    order_nsu = @run.payment_order_nsu.to_s.strip
    return if order_nsu.blank?

    event = InfinitepayWebhookEvent.record(
      payload: { 'order_nsu' => order_nsu, 'captain_run_id' => @run.id },
      source: 'captain_polling'
    )
    Integrations::Infinitepay::VerifyWebhookJob.perform_later(event.id) if event.newly_recorded?
  end

  def envelope_message_params(envelope)
    payload = envelope.message.to_h
    { content: payload['content'], content_type: payload['content_type'],
      content_attributes: payload['content_attributes'] }.compact
  end

  def authorized_preset!(decision)
    allowed = Array(@run.conversation.inbox.captain_inbox&.phase2_payment_preset_ids).map(&:to_i)
    raise PresetNotAllowedError, 'preset is not in the authorized favorites' unless allowed.include?(decision.preset_id.to_i)

    preset = @run.account.payment_presets.find_by(id: decision.preset_id)
    raise PresetNotAllowedError, 'preset does not belong to the account' if preset.nil?

    preset
  end

  # HTTP happens here, outside any lock; the message is composed later inside
  # the terminal transaction with the run idempotency key.
  def generate_charge(preset)
    Integrations::Infinitepay::CreateLinkService.new(
      account: @run.account,
      conversation: @run.conversation,
      user: nil,
      amount_cents: preset.amount_cents,
      description: preset.description,
      # The preset->template link ships on develop (e37f9ad6c2); this worktree
      # base predates it, so resolve it defensively for both bases.
      whatsapp_interactive_template_id: preset.try(:whatsapp_interactive_template_id)
    ).perform_without_message
  end

  def charge_message_params(charge)
    attrs = charge[:message_attributes]
    { content: attrs[:content], content_type: attrs[:content_type],
      content_attributes: attrs[:content_attributes] }.compact
  end

  def create_private_note(conversation, reason:)
    conversation.messages.create!(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :outgoing,
      private: true,
      content: I18n.t('conversations.captain.payment_review_note', reason: reason.to_s)
    )
  end
end
