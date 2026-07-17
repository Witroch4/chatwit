# Nudge-only listener for the durable payment-review flow. On the async event it
# hands off to WakeService, which under the conversation lock drains the current
# eligible, unclaimed trigger into a run. It never infers state from the event
# payload and never blows up the dispatcher on failure.
class CaptainPaymentReviewListener < BaseListener
  include ::Events::Types

  def conversation_captain_payment_review_requested(event)
    conversation = extract_conversation_and_account(event)[0]
    return if conversation.blank?

    Captain::PaymentReview::WakeService.new(conversation).call
  rescue StandardError => e
    Rails.logger.warn("[CAPTAIN-PAYMENT] Wake nudge failed: #{e.class}: #{e.message}")
  end
end
