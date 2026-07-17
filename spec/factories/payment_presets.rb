FactoryBot.define do
  factory :payment_preset do
    account
    sequence(:name) { |n| "Preset #{n}" }
    amount_cents { 2790 }
    description { 'Análise inicial' }
  end
end
