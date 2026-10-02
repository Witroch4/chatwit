require 'rails_helper'

RSpec.describe Integrations::SocialwiseFlow::CommandLane do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) do
    create(:message, account: account, inbox: inbox, conversation: conversation, content: '/om-windows diegos kotas CC')
  end

  it 'accepts a new incoming slash command' do
    expect(described_class.eligible?(event_name: 'message.created', message: message)).to be(true)
  end

  ['/OM-WINDOWS x', '/OM-Windows Diego', '/om-linux Diego', '  /om-windows Diego', '/om-windows', "/om-windows\nDiego"].each do |content|
    it "accepts #{content.inspect}" do
      message.update!(content: content)
      expect(described_class.eligible?(event_name: 'message.created', message: message)).to be(true)
    end
  end

  it 'ignores edits' do
    expect(described_class.eligible?(event_name: 'message.updated', message: message)).to be(false)
  end

  it 'ignores private notes' do
    message.update!(private: true)
    expect(described_class.eligible?(event_name: 'message.created', message: message)).to be(false)
  end

  it 'ignores outgoing messages' do
    message.update!(message_type: :outgoing)
    expect(described_class.eligible?(event_name: 'message.created', message: message)).to be(false)
  end

  it 'ignores captions of attachments' do
    message.attachments.build(account_id: account.id, file_type: :image, external_url: 'https://example.com/a.png')
    expect(described_class.eligible?(event_name: 'message.created', message: message)).to be(false)
  end

  %w[button_reply list_reply quick_reply_payload postback_payload].each do |interaction|
    it "ignores a #{interaction} click even when its title looks like a command" do
      message.update!(content_attributes: { interaction => { 'id' => '/om-windows', 'title' => '/om-windows x' } })
      expect(described_class.eligible?(event_name: 'message.created', message: message)).to be(false)
    end
  end

  ['/start', '/om-mac x', '/om-windowsx', "oi\n/om-windows x", 'oi /om-windows x', '/1abc', '//om-windows x'].each do |content|
    it "ignores #{content.inspect}" do
      message.update!(content: content)
      expect(described_class.eligible?(event_name: 'message.created', message: message)).to be(false)
    end
  end
end
