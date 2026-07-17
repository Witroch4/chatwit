# Drains the current eligible, unclaimed payment-review trigger for a conversation
# and claims it into a durable run. The async listener is only a nudge: this service
# never infers a generation from a delayed payload — under the conversation lock it
# reads the newest present eligible trigger without a run and claims exactly that one.
#
# Lock order (global): conversation -> trigger -> run.
class Captain::PaymentReview::WakeService
  CANONICAL_LABEL = Captain::PaymentReviewTrigger::CANONICAL_LABEL

  def initialize(conversation)
    @conversation = conversation
  end

  # Returns the run that owns the current edge (new or pre-existing), or nil when
  # there is nothing eligible to claim.
  def call
    locked = @conversation.class.find(@conversation.id)
    locked.with_lock do
      trigger = claimable_trigger(locked.id)
      next if trigger.nil?

      active = active_run(locked.id)
      next note_pending(active, trigger) if active.present?

      claim(locked, trigger)
    end
  end

  private

  def claimable_trigger(conversation_id)
    Captain::PaymentReviewTrigger
      .claimable
      .for_canonical_label
      .where(conversation_id: conversation_id)
      .order(generation: :desc)
      .first
  end

  def active_run(conversation_id)
    Captain::PaymentReviewRun
      .active
      .where(conversation_id: conversation_id, trigger_label: CANONICAL_LABEL)
      .order(generation: :desc)
      .first
  end

  # Re-add during a running generation: record the newest present edge as the
  # pending successor and coalesce; the successor is promoted after the current
  # run reaches a terminal state (see #call being re-invoked).
  def note_pending(active, trigger)
    active.update!(pending_trigger_key: trigger.event_key, retrigger_requested_at: Time.current)
    active
  end

  def claim(conversation, trigger)
    run = Captain::PaymentReviewRun.create!(
      account_id: trigger.account_id,
      conversation_id: conversation.id,
      captain_assistant: conversation.inbox.captain_assistant,
      trigger_label: trigger.trigger_label,
      trigger_key: trigger.event_key,
      generation: trigger.generation,
      triggered_at: trigger.activated_at,
      trigger_message_id: trigger.trigger_message_id,
      decision_watermark_message_id: trigger.trigger_message_id,
      payment_context_id: trigger.payment_context_id,
      payment_context_version: trigger.payment_context_version,
      status: :queued
    )
    trigger.update!(state: :claimed, run: run)
    Captain::PaymentReviewJob.perform_later(run.id)
    run
  end
end
