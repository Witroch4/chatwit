# frozen_string_literal: true

# Single local reconciler per (provider, order_nsu) — spec §11.3.
#
# Only an official receipt (`source=infinitepay_payment_check`, status paid)
# enters here; verified webhooks and Captain polling both feed this same
# service. Each milestone is recorded independently, so a crash at any stage
# resumes without duplicating earlier effects; an already-paid PaymentLink
# never skips later milestones.
class Integrations::Infinitepay::ReconciliationService
  class UnverifiedReceiptError < StandardError; end
  class PaymentLinkMissingError < StandardError; end

  VERIFIED_SOURCE = 'infinitepay_payment_check'

  def initialize(order_nsu:, receipt:, raw_payload: {})
    @order_nsu = order_nsu.to_s
    @receipt = receipt.to_h
    @raw_payload = raw_payload.to_h
  end

  def perform
    validate_receipt!

    reconciliation = PaymentReconciliation.find_or_create_by!(provider: 'infinitepay', order_nsu: @order_nsu)
    payment_link = PaymentLink.find_by(order_nsu: @order_nsu)
    raise PaymentLinkMissingError, @order_nsu if payment_link.nil?

    effects = Integrations::Infinitepay::WebhookProcessorService.new(
      payment_link: payment_link, receipt: @receipt, raw_payload: @raw_payload
    )

    run_milestone(reconciliation, 'verified') { reconciliation.update!(receipt: @receipt) }
    run_milestone(reconciliation, 'chatwit_payment_link_applied') { effects.apply_payment_link! }
    run_milestone(reconciliation, 'confirmation_message_accepted') { effects.send_confirmation_message! }
    run_milestone(reconciliation, 'push_dispatched') { effects.send_payment_push! }
    # One Platform forward both resumes the flow session and delivers the
    # Socialwise event; the two milestones are recorded around the same call.
    run_milestone(reconciliation, 'session_reconciled') { effects.forward_to_socialwise! }
    run_milestone(reconciliation, 'socialwise_forwarded') { nil }
    run_milestone(reconciliation, 'jusmonitoria_forwarded') { effects.forward_to_jusmonitoria! }
    run_milestone(reconciliation, 'completed') { nil }
    reconciliation
  end

  private

  def validate_receipt!
    return if @receipt['status'] == 'paid' && @receipt['source'] == VERIFIED_SOURCE

    raise UnverifiedReceiptError, 'reconciliation requires a paid infinitepay_payment_check receipt'
  end

  def run_milestone(reconciliation, name)
    return if reconciliation.milestone_done?(name)

    yield
    reconciliation.record_milestone!(name)
  end
end
