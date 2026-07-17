class CaptainListener < BaseListener
  include ::Events::Types

  def account_created(event)
    Captain::PaymentReview::LabelProvisioner.provision!(event.data.fetch(:account))
  rescue StandardError => e
    Rails.logger.warn("[CAPTAIN-PAYMENT] Failed to provision new account label: #{e.message}")
  end

  def conversation_resolved(event)
    conversation = extract_conversation_and_account(event)[0]
    assistant = conversation.inbox.captain_assistant

    return unless conversation.inbox.captain_auto_response_active?

    Captain::Llm::ContactNotesService.new(assistant, conversation).generate_and_update_notes if assistant.config['feature_memory'].present?
    Captain::Llm::ConversationFaqService.new(assistant, conversation).generate_and_deduplicate if assistant.config['feature_faq'].present?
  end
end
