class PaymentPreset < ApplicationRecord
  belongs_to :account
  belongs_to :whatsapp_interactive_template, optional: true

  validates :name, presence: true
  validates :amount_cents, presence: true, numericality: { greater_than: 0 }
  validates :description, presence: true
  validate :whatsapp_interactive_template_belongs_to_account

  private

  def whatsapp_interactive_template_belongs_to_account
    return if whatsapp_interactive_template_id.blank?
    return if account.whatsapp_interactive_templates.exists?(id: whatsapp_interactive_template_id)

    errors.add(:whatsapp_interactive_template, 'must belong to the same account')
  end
end
