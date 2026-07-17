# frozen_string_literal: true

class Integrations::SocialwiseFlow::OwnershipGuard
  HANDOFF_OWNER = 'captain_payment_phase2'
  EPOCH_KEY = 'socialwise_ownership_epoch'
  HANDOFF_AT_KEY = 'socialwise_handoff_at'
  HANDOFF_BY_KEY = 'socialwise_handoff_by'

  def initialize(conversation)
    @conversation = conversation
  end

  def socialwise_owned?
    with_locked_ownership_snapshot do |locked_conversation, attributes|
      socialwise_owned_from?(locked_conversation, attributes)
    end
  end

  def snapshot_epoch
    epoch_from(reload_conversation.additional_attributes)
  end

  def can_publish?(epoch:)
    return false unless valid_epoch?(epoch)

    with_locked_ownership_snapshot do |locked_conversation, attributes|
      epoch_from(attributes) == epoch && socialwise_owned_from?(locked_conversation, attributes)
    end
  end

  def with_publish_lock(epoch:)
    return false unless valid_epoch?(epoch)

    with_locked_ownership_snapshot do |locked_conversation, attributes|
      next false unless epoch_from(attributes) == epoch && socialwise_owned_from?(locked_conversation, attributes)

      yield locked_conversation, attributes
      true
    end
  end

  def pause_for_phase2!
    locked_conversation = reload_conversation
    installed_fence = nil
    locked_conversation.with_lock do
      handoff_at = Time.current.iso8601(6)
      epoch = epoch_from(locked_conversation.additional_attributes) + 1
      attributes = (locked_conversation.additional_attributes || {}).merge(
        HANDOFF_AT_KEY => handoff_at,
        HANDOFF_BY_KEY => HANDOFF_OWNER,
        EPOCH_KEY => epoch
      )

      locked_conversation.update!(
        additional_attributes: attributes,
        status: :open,
        waiting_since: nil
      )
      installed_fence = { HANDOFF_AT_KEY => handoff_at, HANDOFF_BY_KEY => HANDOFF_OWNER, EPOCH_KEY => epoch }
    end

    clear_disposable_debounce_keys(installed_fence)
    true
  end

  def release_for_resolve!(cutoff:)
    locked_conversation = reload_conversation
    locked_conversation.with_lock do
      current_trigger = present_trigger
      trigger = releasable_trigger(current_trigger, cutoff)
      attributes = locked_conversation.additional_attributes || {}
      release_handoff = handoff_present_at?(attributes, cutoff)
      next false unless release_required?(trigger, release_handoff)

      trigger&.update!(state: :cancelled, deactivated_at: Time.current)

      locked_conversation.update!(
        additional_attributes: released_attributes(attributes, release_handoff),
        label_list: released_labels(locked_conversation.label_list.to_a, current_trigger, trigger)
      )
      true
    end
  end

  private

  attr_reader :conversation

  def reload_conversation
    conversation.class.find(conversation.id)
  end

  def with_locked_ownership_snapshot
    locked_conversation = reload_conversation
    locked_conversation.with_lock do
      locked_conversation.reload
      attributes = locked_conversation.additional_attributes || {}

      yield locked_conversation, attributes
    end
  end

  def socialwise_owned_from?(locked_conversation, attributes)
    attributes[HANDOFF_AT_KEY].blank? &&
      !eligible_trigger_present?(locked_conversation.id) &&
      !active_run_present?(locked_conversation.id)
  end

  # A queued/running payment-review run keeps the fence during a kill-switch drain,
  # even after the raw label is gone.
  def active_run_present?(conversation_id)
    Captain::PaymentReviewRun
      .active
      .exists?(conversation_id: conversation_id, trigger_label: Captain::PaymentReviewTrigger::CANONICAL_LABEL)
  end

  def eligible_trigger_present?(conversation_id)
    Captain::PaymentReviewTrigger
      .eligible
      .present_generation
      .for_canonical_label
      .exists?(conversation_id: conversation_id)
  end

  def present_trigger
    Captain::PaymentReviewTrigger
      .present_generation
      .for_canonical_label
      .where(conversation_id: conversation.id)
      .lock
      .order(generation: :desc)
      .first
  end

  def releasable_trigger(trigger, cutoff)
    return if trigger&.activated_at.blank?

    trigger if trigger.activated_at <= cutoff
  end

  def release_required?(trigger, release_handoff)
    trigger.present? || release_handoff
  end

  def released_attributes(attributes, release_handoff)
    updated_attributes = attributes.merge(EPOCH_KEY => epoch_from(attributes) + 1)
    return updated_attributes unless release_handoff

    updated_attributes.except(HANDOFF_AT_KEY, HANDOFF_BY_KEY)
  end

  def released_labels(labels, current_trigger, trigger)
    return labels if current_trigger.present? && trigger.blank?

    labels - [Captain::PaymentReviewTrigger::CANONICAL_LABEL]
  end

  def handoff_present_at?(attributes, cutoff)
    handoff_at = attributes[HANDOFF_AT_KEY]
    return false if handoff_at.blank?

    Time.zone.parse(handoff_at.to_s) <= cutoff
  rescue ArgumentError, TypeError
    false
  end

  def epoch_from(attributes)
    value = attributes&.dig(EPOCH_KEY)
    valid_epoch?(value) ? value : 0
  end

  def valid_epoch?(value)
    value.is_a?(Integer) && value >= 0
  end

  def clear_disposable_debounce_keys(installed_fence)
    locked_conversation = reload_conversation
    locked_conversation.with_lock do
      locked_conversation.reload
      attributes = locked_conversation.additional_attributes || {}
      next false unless installed_fence.all? { |key, value| attributes[key] == value }

      disposable_debounce_keys.each do |key|
        Redis::Alfred.delete(key)
      rescue StandardError => e
        Rails.logger.warn "[SOCIALWISE-FLOW] Failed to clear debounce key #{key}: #{e.class}: #{e.message}"
      end

      true
    end
  rescue StandardError => e
    Rails.logger.warn(
      "[SOCIALWISE-FLOW] Failed to clear debounce state for conversation #{conversation.id}: #{e.class}: #{e.message}"
    )
    false
  end

  def disposable_debounce_keys
    [
      Redis::Alfred::SOCIALWISE_DEBOUNCE_MESSAGES,
      Redis::Alfred::SOCIALWISE_DEBOUNCE_FIRST_AT,
      Redis::Alfred::SOCIALWISE_DEBOUNCE_LAST_AT,
      Redis::Alfred::SOCIALWISE_DEBOUNCE_ACTIVE
    ].map { |key| format(key, conversation_id: conversation.id) }
  end
end
