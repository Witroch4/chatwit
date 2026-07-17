# == Schema Information
#
# Table name: captain_inboxes
#
#  id                   :bigint           not null, primary key
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  captain_assistant_id :bigint           not null
#  inbox_id             :bigint           not null
#
# Indexes
#
#  index_captain_inboxes_on_captain_assistant_id               (captain_assistant_id)
#  index_captain_inboxes_on_captain_assistant_id_and_inbox_id  (captain_assistant_id,inbox_id) UNIQUE
#  index_captain_inboxes_on_inbox_id                           (inbox_id)
#
class CaptainInbox < ApplicationRecord
  belongs_to :captain_assistant, class_name: 'Captain::Assistant'
  belongs_to :inbox

  enum :mode, { continuous: 0, phase2_only: 1 }, default: :continuous, validate: true

  validates :inbox_id, uniqueness: true

  before_validation :normalize_phase2_settings
  validate :phase2_payment_preset_ids_are_account_presets

  # Operator prompt when set, otherwise the shared editable default (Emenda §E3).
  def phase2_prompt_or_default
    phase2_prompt.presence || Captain::PaymentReview::DEFAULT_PROMPT
  end

  private

  # phase2_* fields are only meaningful for phase2_only inboxes; blank them out
  # for continuous. For phase2_only, coerce integer-like ids submitted as strings
  # (form params) into integers so validation and storage stay consistent.
  def normalize_phase2_settings
    if phase2_only?
      self.phase2_pix_key = phase2_pix_key.to_s.strip.presence
      self.phase2_payment_preset_ids = Array(phase2_payment_preset_ids).map { |value| coerce_preset_id(value) }
    else
      self.phase2_model = nil
      self.phase2_prompt = nil
      self.phase2_pix_key = nil
      self.phase2_payment_preset_ids = []
    end
  end

  def coerce_preset_id(value)
    return value if value.is_a?(Integer)

    Integer(value, exception: false) || value
  end

  def phase2_payment_preset_ids_are_account_presets
    return unless phase2_only?

    ids = phase2_payment_preset_ids
    unless ids.is_a?(Array) && ids.all?(Integer)
      errors.add(:phase2_payment_preset_ids, 'must be an array of integers')
      return
    end
    return if ids.empty?

    known = PaymentPreset.where(account_id: inbox&.account_id, id: ids).pluck(:id)
    errors.add(:phase2_payment_preset_ids, 'must reference payment presets from the same account') if (ids - known).any?
  end
end
