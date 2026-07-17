# Durable inbox for raw InfinitePay events (spec §11.2): the public webhook
# only persists here; verification/effects happen asynchronously and only from
# an official payment_check receipt.
class InfinitepayWebhookEvent < ApplicationRecord
  enum :status, { received: 0, awaiting_verification: 1, processed: 2, discarded: 3 }

  validates :order_nsu, presence: true
  validates :event_hash, presence: true, uniqueness: true

  attr_accessor :newly_recorded

  def self.record(payload:, source: 'webhook')
    canonical = JSON.generate(payload.to_h.sort.to_h)
    digest = Digest::SHA256.hexdigest("infinitepay:#{source}:#{canonical}")
    event = create!(
      order_nsu: payload['order_nsu'].to_s,
      source: source,
      event_hash: digest,
      payload: payload
    )
    event.newly_recorded = true
    event
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
    existing = find_by(event_hash: digest)
    raise e if existing.nil?

    existing.tap { |event_record| event_record.newly_recorded = false }
  end

  def newly_recorded?
    newly_recorded == true
  end
end
