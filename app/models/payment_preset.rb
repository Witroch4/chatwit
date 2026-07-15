class PaymentPreset < ApplicationRecord
  belongs_to :account
  belongs_to :whatsapp_interactive_template, optional: true

  validates :name, presence: true
  validates :amount_cents, presence: true, numericality: { greater_than: 0 }
  validates :description, presence: true
end
