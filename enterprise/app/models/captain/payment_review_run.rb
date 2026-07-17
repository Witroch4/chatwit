class Captain::PaymentReviewRun < ApplicationRecord
  self.table_name = 'captain_payment_review_runs'

  LEASE_DURATION = 2.minutes
  ACTIVE_STATUSES = %w[queued running].freeze

  enum :status, { queued: 0, running: 1, completed: 2, failed: 3, superseded: 4 }, validate: true
  enum :outcome,
       { paid: 0, no_action: 1, replied: 2, cta_accepted: 3, pix_key_accepted: 4,
         status_accepted: 5, handoff_required: 6, superseded: 7, payment_preset_accepted: 8 },
       validate: { allow_nil: true }, prefix: :outcome

  belongs_to :account, class_name: '::Account'
  belongs_to :conversation, class_name: '::Conversation'
  belongs_to :captain_assistant, class_name: 'Captain::Assistant', optional: true
  belongs_to :response_message, class_name: '::Message', optional: true
  has_one :trigger, class_name: 'Captain::PaymentReviewTrigger', foreign_key: :run_id, inverse_of: :run,
                    dependent: :nullify

  attr_readonly :account_id, :conversation_id, :trigger_label, :trigger_key, :generation,
                :triggered_at, :trigger_message_id

  validates :trigger_label, presence: true
  validates :trigger_key, presence: true, uniqueness: true
  validates :generation, numericality: { only_integer: true, greater_than: 0 }
  validates :attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :assistant_belongs_to_account
  validate :single_active_run_per_conversation_label, on: :create

  scope :active, -> { where(status: statuses.values_at('queued', 'running')) }

  # A worker owns the run only while its token matches and the lease has not expired.
  def lease_held_by?(token)
    running? && token.present? && execution_token == token && lease_expires_at.present? && lease_expires_at.future?
  end

  private

  def assistant_belongs_to_account
    return if captain_assistant.blank? || captain_assistant.account_id == account_id

    errors.add(:captain_assistant_id, 'must belong to the run account')
  end

  def single_active_run_per_conversation_label
    return unless queued? || running?

    scope = self.class.active.where(conversation_id: conversation_id, trigger_label: trigger_label)
    scope = scope.where.not(id: id) if persisted?
    errors.add(:base, 'an active run already exists for this conversation label') if scope.exists?
  end
end
