FactoryBot.define do
  factory :captain_payment_review_trigger, class: 'Captain::PaymentReviewTrigger' do
    association :conversation
    account { conversation.account }
    trigger_label { Captain::PaymentReviewTrigger::CANONICAL_LABEL }
    sequence(:generation)
    state { :eligible }
    source { :manual }
    activated_at { Time.current }
    sequence(:event_key) { |number| "captain-payment-review:factory:#{number}" }
  end
end
