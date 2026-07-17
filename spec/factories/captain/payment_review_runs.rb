FactoryBot.define do
  factory :captain_payment_review_run, class: 'Captain::PaymentReviewRun' do
    association :conversation
    account { conversation.account }
    trigger_label { Captain::PaymentReviewTrigger::CANONICAL_LABEL }
    sequence(:trigger_key) { |number| "captain-payment-review:run:#{number}" }
    sequence(:generation)
    triggered_at { Time.current }
    status { :queued }
    attempts { 0 }
  end
end
