# Resumable verification worker for quarantined InfinitePay events.
#
# Local links (chatwit-*) are verified against the Platform official
# `/payment-events/verify` endpoint using only expected authenticated metadata;
# a paid receipt feeds the local milestone reconciler. Flow charges (no local
# PaymentLink anchor) are forwarded to the Platform, which runs its own
# official verification server-side (raw claims are never promoted anywhere).
class Integrations::Infinitepay::VerifyWebhookJob < ApplicationJob
  class VerificationPending < StandardError; end

  queue_as :default

  retry_on VerificationPending, wait: :polynomially_longer, attempts: 8

  def perform(event_id)
    event = InfinitepayWebhookEvent.find_by(id: event_id)
    return if event.nil? || event.processed? || event.discarded?

    payment_link = PaymentLink.find_by(order_nsu: event.order_nsu)
    return forward_flow_event(event) if payment_link.nil?

    receipt = Integrations::Infinitepay::VerifyEventService.new(payment_link: payment_link).receipt
    case receipt['status']
    when 'paid'
      Integrations::Infinitepay::ReconciliationService.new(
        order_nsu: event.order_nsu, receipt: receipt, raw_payload: event.payload
      ).perform
      event.update!(status: :processed, verified_at: Time.current)
    when 'pending'
      event.update!(status: :awaiting_verification)
      raise VerificationPending, event.order_nsu
    else
      event.update!(status: :discarded)
    end
  end

  private

  # Flow charges (sw-*) have no Chatwit anchor: the Platform owns the financial
  # truth and re-verifies internally (raw ingress closed in Task 12a). The
  # forward keeps the resume path alive without any local financial effect.
  def forward_flow_event(event)
    Integrations::Infinitepay::WebhookProcessorService.forward_raw_flow_event(event.payload)
    event.update!(status: :processed, verified_at: Time.current)
  end
end
