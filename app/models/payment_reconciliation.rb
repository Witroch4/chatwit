# Single local milestone ledger per (provider, order_nsu) — spec §11.3.
# Verified webhooks and Captain polling feed the same reconciler; each stage is
# independently resumable and never re-applied once recorded.
class PaymentReconciliation < ApplicationRecord
  MILESTONES = %w[
    verified session_reconciled chatwit_payment_link_applied confirmation_message_accepted
    push_dispatched socialwise_forwarded jusmonitoria_forwarded completed
  ].freeze

  validates :order_nsu, presence: true, uniqueness: { scope: :provider }

  def milestone_done?(name)
    milestones[name.to_s].present?
  end

  def record_milestone!(name)
    raise ArgumentError, "unknown milestone #{name}" unless MILESTONES.include?(name.to_s)

    update!(milestones: milestones.merge(name.to_s => Time.current.utc.iso8601))
  end
end
