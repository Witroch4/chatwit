require 'rails_helper'

RSpec.describe Integrations::Socialwise::InstagramResponseProcessor do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_instagram, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox) }
  let(:message) { create(:message, account: account, inbox: channel.inbox, conversation: conversation) }

  it 'does not create fallback output when ownership is already lost' do
    message

    expect do
      described_class.process('invalid', message, ownership_check: -> { false })
    end.not_to change(conversation.messages, :count)
  end

  it 'revalidates after rich-message persistence and before the provider call' do
    ownership_lost = false
    allow(described_class).to receive(:create_rich_outgoing_message).and_wrap_original do |method, *args|
      outgoing_message = method.call(*args)
      ownership_lost = true
      outgoing_message
    end
    expect(Instagram::RichMessageService).not_to receive(:new)

    described_class.send(
      :send_quick_replies,
      {
        'text' => 'Choose one',
        'quick_replies' => [{ 'content_type' => 'text', 'title' => 'One', 'payload' => 'one' }]
      },
      message,
      platform: :instagram,
      ownership_check: -> { !ownership_lost }
    )

    expect(conversation.messages.outgoing).to exist
  end

  it 'revalidates after constructing the provider service and before performing it' do
    ownership_lost = false
    provider = instance_double(Instagram::RichMessageService)
    allow(Instagram::RichMessageService).to receive(:new) do
      ownership_lost = true
      provider
    end
    expect(provider).not_to receive(:perform)

    described_class.send(
      :send_quick_replies,
      {
        'text' => 'Choose one',
        'quick_replies' => [{ 'content_type' => 'text', 'title' => 'One', 'payload' => 'one' }]
      },
      message,
      platform: :instagram,
      ownership_check: -> { !ownership_lost }
    )
  end
end
