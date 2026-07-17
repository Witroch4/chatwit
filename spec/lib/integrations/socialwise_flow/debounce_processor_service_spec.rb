require 'rails_helper'

RSpec.describe Integrations::SocialwiseFlow::DebounceProcessorService do
  let(:service) do
    described_class.new(
      event_name: 'message.created',
      hook: hook,
      event_data: { message: message },
      concatenated_content: 'first\nsecond',
      ownership_epoch: 0
    )
  end

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :open) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation) }
  let(:hook) do
    create(
      :integrations_hook,
      account: account,
      inbox: inbox,
      app_id: 'socialwise_flow',
      settings: { 'language' => 'pt-BR' }
    )
  end
  let(:http_response) { instance_double(HTTParty::Response, success?: true, parsed_response: { 'text' => 'late response' }) }

  def create_eligible_trigger
    create(:captain_payment_review_trigger, conversation: conversation, account: account, state: :eligible)
  end

  it 'blocks ingress before HTTP for an eligible present trigger' do
    create_eligible_trigger
    expect(HTTParty).not_to receive(:post)
    expect(service).not_to receive(:process_response)

    service.perform
  end

  it 'continues for an ineligible trigger' do
    create(:captain_payment_review_trigger, conversation: conversation, account: account, state: :ineligible)
    allow(service).to receive(:get_response).and_return({ 'text' => 'response' })
    expect(service).to receive(:process_response).with(message, { 'text' => 'response' }, epoch: 0)

    service.perform
  end

  it 'drops the response when an eligible trigger appears during HTTP' do
    allow(HTTParty).to receive(:post) do
      create_eligible_trigger
      http_response
    end
    expect(service).not_to receive(:process_response)

    service.perform
  end

  it 'drops the response when the epoch changes during HTTP' do
    allow(HTTParty).to receive(:post) do
      conversation.update!(additional_attributes: { 'socialwise_ownership_epoch' => 1 })
      http_response
    end
    expect(service).not_to receive(:process_response)

    service.perform
  end

  it 'never recaptures the current epoch for an old batch after pause and resolve' do
    allow(Redis::Alfred).to receive(:delete).and_raise(Redis::BaseError, 'unavailable')
    guard = Integrations::SocialwiseFlow::OwnershipGuard.new(conversation)
    guard.pause_for_phase2!
    guard.release_for_resolve!(cutoff: Time.current)

    expect(conversation.reload.additional_attributes['socialwise_ownership_epoch']).to eq(2)
    expect(HTTParty).not_to receive(:post)
    expect(service).not_to receive(:process_response)

    service.perform
  end
end
