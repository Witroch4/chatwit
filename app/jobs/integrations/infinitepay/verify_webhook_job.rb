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

    receipt = Integrations::Infinitepay::VerifyEventService.new(payment_link: payment_link, raw_payload: event.payload).receipt
    case receipt['status']
    when 'paid'
      Integrations::Infinitepay::ReconciliationService.new(
        order_nsu: event.order_nsu, receipt: receipt, raw_payload: event.payload
      ).perform
      event.update!(status: :processed, verified_at: Time.current)
    else
      # pending/unknown both retry with backoff: card captures propagate with
      # delay on the provider side; the event stays visible for ops either way.
      event.update!(status: :awaiting_verification)
      raise VerificationPending, "#{event.order_nsu}:#{receipt['reasonCode']}"
    end
  end

  private

  # Flow charges (sw-*) have no Chatwit anchor: the Platform owns the financial
  # truth and re-verifies internally (raw ingress closed in Task 12a). The
  # forward keeps the resume path alive without any local financial effect.
  # The Platform answer drives the rest: not yet verified (provider delay) or
  # unreachable → re-forward with backoff; verified → push the agents.
  def forward_flow_event(event)
    response = Integrations::Infinitepay::WebhookProcessorService.forward_raw_flow_event(event.payload)
    answer = platform_answer(response)
    if retry_flow_forward?(response, answer)
      event.update!(status: :awaiting_verification)
      raise VerificationPending, "#{event.order_nsu}:platform_#{response.success? ? 'unverified' : response.code}"
    end

    event.update!(status: :processed, verified_at: Time.current)
    Integrations::Infinitepay::FlowPaymentPushService.new(order_nsu: event.order_nsu, answer: answer).perform
  rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError => e
    event.update!(status: :awaiting_verification)
    raise VerificationPending, "#{event.order_nsu}:#{e.class.name}"
  end

  # No response = SOCIALWISE_WEBHOOK_URL not configured: nothing to retry.
  # (Type check, not #nil?: HTTParty answers nil? == true for an empty body.)
  def retry_flow_forward?(response, answer)
    return false unless response.is_a?(HTTParty::Response)
    return true unless response.success?

    !ActiveModel::Type::Boolean.new.cast(answer['verified']) &&
      ActiveModel::Type::Boolean.new.cast(answer['retryable'])
  end

  def platform_answer(response)
    return {} unless response.is_a?(HTTParty::Response)

    parsed = response.parsed_response
    parsed = JSON.parse(parsed) if parsed.is_a?(String)
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end
end
