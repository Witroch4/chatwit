module Labelable
  extend ActiveSupport::Concern

  included do
    acts_as_taggable_on :labels
  end

  def update_labels(labels = nil, source: :manual, payment_context: nil)
    perform_label_mutation(:replace, labels, source: source, payment_context: payment_context)
  end

  def add_labels(new_labels = nil, source: :manual, payment_context: nil)
    return if new_labels.blank?

    perform_label_mutation(:add, new_labels, source: source, payment_context: payment_context)
  end

  def remove_labels(labels = nil, source: :manual)
    return if labels.blank?

    perform_label_mutation(:remove, labels, source: source)
  end

  private

  def perform_label_mutation(operation, requested_labels, source:, payment_context: nil)
    return perform_extended_label_mutation(operation, requested_labels, source, payment_context) if respond_to?(:label_mutation_service_class, true)

    with_lock do
      reload
      old_labels = label_list.to_a
      parsed_labels = ActsAsTaggableOn.default_parser.new(requested_labels).parse.to_a
      new_labels = case operation
                   when :add then old_labels | parsed_labels
                   when :remove then old_labels - parsed_labels
                   when :replace then parsed_labels
                   end
      update!(label_list: new_labels)
    end
  end

  def perform_extended_label_mutation(operation, requested_labels, source, payment_context)
    label_mutation_service_class.new(
      conversation: self,
      labels: requested_labels,
      source: source,
      payment_context: payment_context
    ).public_send("#{operation}!")
    reload
    true
  end
end
