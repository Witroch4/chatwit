require 'rails_helper'

RSpec.describe Messages::IdempotentCreateService do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:key) { 'socialwise-flow:session-1:node-2:1' }

  def build_service(params)
    described_class.new(
      user: agent_bot,
      conversation: conversation,
      params: ActionController::Parameters.new(params.merge(idempotency_key: key))
    )
  end

  def perform_with(params)
    build_service(params).perform
  end

  it 'stores an immutable payload hash with the created message' do
    message = perform_with(content: 'payment CTA')

    expect(message.idempotency_key).to eq(key)
    expect(message.idempotency_payload_hash).to match(/\A[0-9a-f]{64}\z/)
  end

  it 'keeps the idempotency metadata readonly after creation' do
    message = perform_with(content: 'payment CTA')

    expect(message.class.readonly_attributes).to include('idempotency_key', 'idempotency_payload_hash')
  end

  it 'returns the existing message for the same canonical payload' do
    first = perform_with(content: 'payment CTA', content_attributes: { b: 2, a: 1 })
    retry_message = perform_with(content_attributes: { a: 1, b: 2 }, content: 'payment CTA')

    expect(retry_message).to eq(first)
    expect(conversation.messages.where(idempotency_key: key).count).to eq(1)
  end

  it 'raises a conflict for a different payload' do
    perform_with(content: 'payment CTA')

    expect do
      perform_with(content: 'different CTA')
    end.to raise_error(described_class::ConflictError)
  end

  it 'does not reserve or compare the provider source id' do
    first = perform_with(content: 'payment CTA', source_id: 'caller-controlled-id')
    retry_message = perform_with(content: 'payment CTA', source_id: 'provider-assigned-id')

    expect(first.source_id).to be_nil
    expect(retry_message).to eq(first)
  end

  it 'resolves the winning row after a concurrent unique-key violation' do
    existing = perform_with(content: 'payment CTA')
    retry_service = build_service(content: 'payment CTA')

    allow(retry_service).to receive(:existing_message).and_return(nil, existing)
    allow(Messages::MessageBuilder).to receive(:new).and_raise(ActiveRecord::RecordNotUnique)

    expect(retry_service.perform).to eq(existing)
  end

  it 'does not mask an unrelated unique-key violation as an idempotency conflict' do
    service = build_service(content: 'payment CTA')

    allow(service).to receive(:existing_message).and_return(nil)
    allow(Messages::MessageBuilder).to receive(:new).and_raise(ActiveRecord::RecordNotUnique)

    expect { service.perform }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
