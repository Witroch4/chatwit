require 'rails_helper'

RSpec.describe 'Webhooks::Infinitepay', type: :request do
  let(:payload) do
    {
      order_nsu: 'chatwit-1-2-abc123',
      amount: 999_999,
      paid_amount: 999_999,
      invoice_slug: 'evil-slug',
      receipt_url: 'https://evil.example/receipt'
    }
  end

  it 'commits one durable event, answers 200 and produces no financial effect' do
    account = create(:account)
    conversation = create(:conversation, account: account)
    link = PaymentLink.create!(account: account, conversation: conversation, order_nsu: payload[:order_nsu],
                               amount_cents: 500, description: 'Análise', checkout_url: 'x', status: 'pending')

    expect do
      post '/webhooks/infinitepay', params: payload, as: :json
    end.to change(InfinitepayWebhookEvent, :count).by(1)
       .and have_enqueued_job(Integrations::Infinitepay::VerifyWebhookJob)

    expect(response).to have_http_status(:ok)
    event = InfinitepayWebhookEvent.last
    expect(event.order_nsu).to eq(payload[:order_nsu])
    expect(event).to be_received

    link.reload
    expect(link.status).not_to eq('paid')
    expect(link.paid_amount_cents).to be_nil
    expect(conversation.messages.count).to eq(0)
  end

  it 'deduplicates identical events and enqueues at most one verification' do
    post '/webhooks/infinitepay', params: payload, as: :json
    enqueued_before = ActiveJob::Base.queue_adapter.enqueued_jobs.size

    expect do
      post '/webhooks/infinitepay', params: payload, as: :json
    end.to not_change(InfinitepayWebhookEvent, :count)

    expect(response).to have_http_status(:ok)
    expect(ActiveJob::Base.queue_adapter.enqueued_jobs.size).to eq(enqueued_before)
  end

  it 'answers 200 without persisting when order_nsu is missing' do
    expect do
      post '/webhooks/infinitepay', params: { amount: 1 }, as: :json
    end.not_to change(InfinitepayWebhookEvent, :count)

    expect(response).to have_http_status(:ok)
  end
end
