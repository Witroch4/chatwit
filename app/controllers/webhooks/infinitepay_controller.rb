# frozen_string_literal: true

# Raw InfinitePay webhook quarantine (spec §11.2): the controller only commits
# a unique durable event and answers 200. No PaymentLink mutation, message,
# push or integration forward ever happens here — verification and effects run
# asynchronously from the official payment_check receipt.
class Webhooks::InfinitepayController < ActionController::API
  def process_payload
    payload = params.to_unsafe_hash.except(:controller, :action)
    order_nsu = payload['order_nsu'].to_s.strip
    return head :ok if order_nsu.blank?

    event = InfinitepayWebhookEvent.record(payload: payload, source: 'webhook')
    Integrations::Infinitepay::VerifyWebhookJob.perform_later(event.id) if event.newly_recorded?
    head :ok
  rescue StandardError => e
    Rails.logger.error "[INFINITEPAY-WEBHOOK] Error: #{e.class}: #{e.message}"
    head :bad_request
  end
end
