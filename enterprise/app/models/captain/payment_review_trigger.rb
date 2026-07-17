class Captain::PaymentReviewTrigger < ApplicationRecord
  self.table_name = 'captain_payment_review_triggers'

  CANONICAL_LABEL = 'captain_revisar_pagamento'.freeze

  enum :state, { eligible: 0, ineligible: 1, claimed: 2, cancelled: 3, consumed: 4 }, validate: true
  enum :source, { platform_bot: 0, manual: 1, system: 2 }, validate: true, prefix: true

  belongs_to :account, class_name: '::Account'
  belongs_to :conversation, class_name: '::Conversation'
  belongs_to :run, class_name: 'Captain::PaymentReviewRun', optional: true, inverse_of: :trigger

  scope :present_generation, -> { where(deactivated_at: nil) }
  scope :claimable, -> { eligible.present_generation.where(run_id: nil) }
  scope :for_canonical_label, -> { where(trigger_label: CANONICAL_LABEL) }

  attr_readonly :account_id, :conversation_id, :trigger_label, :generation, :source,
                :activated_at, :trigger_message_id, :payment_context_id,
                :payment_context_version, :event_key

  validates :trigger_label, presence: true
  validates :generation,
            numericality: { only_integer: true, greater_than: 0 },
            uniqueness: { scope: :conversation_id }
  validates :event_key, presence: true, uniqueness: true
  validates :activated_at, presence: true
  validates :payment_context_id, presence: true, if: :payment_context_version?
  validates :payment_context_version,
            numericality: { only_integer: true, greater_than: 0 },
            allow_nil: true
  validate :payment_context_is_complete
  validate :account_matches_conversation
  validate :deactivation_matches_state

  private

  def payment_context_is_complete
    return if payment_context_id.blank? == payment_context_version.blank?

    errors.add(:payment_context_id, 'must be provided together with payment_context_version')
  end

  def account_matches_conversation
    return if account_id.blank? || conversation.blank? || account_id == conversation.account_id

    errors.add(:account_id, 'must match the conversation account')
  end

  def deactivation_matches_state
    should_be_deactivated = cancelled? || consumed?
    return if should_be_deactivated == deactivated_at.present?

    errors.add(:deactivated_at, 'must match the trigger state')
  end
end
