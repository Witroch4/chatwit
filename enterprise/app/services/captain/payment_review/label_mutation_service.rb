class Captain::PaymentReview::LabelMutationService
  class Phase2DisabledError < StandardError; end
  class InvalidPaymentContextError < StandardError; end

  Result = Data.define(:labels, :added, :removed, :trigger)

  def initialize(conversation:, labels:, source:, payment_context: nil)
    @conversation = conversation
    @labels = normalize_labels(labels)
    @source = source.to_sym
    @payment_context = normalize_payment_context(payment_context)
    validate_source!
  end

  def add!
    mutate!(:add)
  end

  def remove!
    mutate!(:remove)
  end

  def replace!
    mutate!(:replace)
  end

  private

  attr_reader :conversation, :labels, :source, :payment_context

  def mutate!(operation)
    locked_conversation = conversation.class.find(conversation.id)
    result = locked_conversation.with_lock do
      locked_conversation.reload
      old_labels = locked_conversation.label_list.to_a
      new_labels = labels_after(operation, old_labels)
      added = new_labels - old_labels
      removed = old_labels - new_labels
      gate_reason = Captain::PaymentReview::FeatureGate.new(locked_conversation).reason

      enforce_platform_gate!(gate_reason, added)
      trigger = persist_canonical_edge!(locked_conversation, old_labels, new_labels, gate_reason == :eligible)
      locked_conversation.update!(label_list: new_labels) if old_labels != new_labels

      Result.new(labels: new_labels, added: added, removed: removed, trigger: trigger)
    end

    dispatch_wake_nudge(locked_conversation) if result.trigger&.eligible?
    result
  end

  # After committing an eligible rising edge, nudge the durable run flow. The event
  # is only a signal; WakeService drains under the conversation lock (Task 10).
  def dispatch_wake_nudge(locked_conversation)
    Rails.configuration.dispatcher.dispatch(
      Events::Types::CONVERSATION_CAPTAIN_PAYMENT_REVIEW_REQUESTED,
      Time.zone.now,
      conversation: locked_conversation
    )
  end

  def labels_after(operation, old_labels)
    case operation
    when :add
      old_labels | labels
    when :remove
      old_labels - labels
    when :replace
      labels
    end
  end

  def enforce_platform_gate!(gate_reason, added_labels)
    return unless source == :platform_bot && added_labels.include?(canonical_label)
    return if gate_reason == :eligible

    raise Phase2DisabledError, gate_reason.to_s
  end

  def persist_canonical_edge!(locked_conversation, old_labels, new_labels, eligible)
    was_present = old_labels.include?(canonical_label)
    is_present = new_labels.include?(canonical_label)
    return if was_present == is_present

    if is_present
      create_trigger!(locked_conversation, eligible)
    else
      cancel_present_trigger!(locked_conversation)
    end
  end

  def create_trigger!(locked_conversation, eligible)
    generation = locked_conversation.captain_payment_review_triggers.maximum(:generation).to_i + 1
    now = Time.current

    locked_conversation.captain_payment_review_triggers.create!(
      account: locked_conversation.account,
      trigger_label: canonical_label,
      generation: generation,
      state: eligible ? :eligible : :ineligible,
      source: source,
      activated_at: now,
      trigger_message_id: locked_conversation.messages.maximum(:id),
      payment_context_id: payment_context&.fetch(:id),
      payment_context_version: payment_context&.fetch(:version),
      event_key: "captain-payment-review:#{locked_conversation.id}:#{generation}"
    )
  end

  def cancel_present_trigger!(locked_conversation)
    trigger = locked_conversation.captain_payment_review_triggers
                                 .for_canonical_label
                                 .present_generation
                                 .lock
                                 .first
    return if trigger.blank?

    trigger.update!(state: :cancelled, deactivated_at: Time.current)
    trigger
  end

  def normalize_labels(value)
    ActsAsTaggableOn.default_parser.new(value).parse.to_a
  end

  def normalize_payment_context(value)
    return if value.blank?

    raise InvalidPaymentContextError, 'payment_context is reserved for the Platform Bot' unless source.to_sym == :platform_bot

    context = payment_context_hash(value)
    raise InvalidPaymentContextError, 'payment_context must contain a string id and positive integer version' unless valid_payment_context?(context)

    { id: context[:id].strip, version: context[:version] }
  end

  def payment_context_hash(value)
    raw_context = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value.to_h
    raw_context.symbolize_keys.slice(:id, :version)
  end

  def valid_payment_context?(context)
    context[:id].is_a?(String) && context[:id].strip.present? &&
      context[:version].is_a?(Integer) && context[:version].positive?
  end

  def validate_source!
    return if Captain::PaymentReviewTrigger.sources.key?(source.to_s)

    raise ArgumentError, "Unknown payment review trigger source: #{source}"
  end

  def canonical_label
    Captain::PaymentReviewTrigger::CANONICAL_LABEL
  end
end
