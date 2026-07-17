require 'rails_helper'

RSpec.describe Integrations::SocialwiseFlow::WhatsappResponseProcessor do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, account: account, inbox: conversation.inbox, conversation: conversation) }

  it 'does not create a fallback or call a provider when ownership is already lost' do
    message
    expect(Whatsapp::SendOnWhatsappService).not_to receive(:new)

    expect do
      described_class.process('invalid', message, ownership_check: -> { false })
    end.not_to change(conversation.messages, :count)
  end

  it 'revalidates after dashboard persistence and before the provider call' do
    ownership_checks = 0
    expect(Whatsapp::SendOnWhatsappService).not_to receive(:new)

    described_class.send(
      :send_text_message,
      { 'type' => 'text', 'text' => { 'body' => 'authorized text' } },
      message,
      ownership_check: -> { (ownership_checks += 1) <= 2 }
    )

    expect(conversation.messages.outgoing.where(content: 'authorized text')).to exist
  end

  it 'revalidates immediately before the direct template HTTP call' do
    channel = instance_double(
      Channel::Whatsapp,
      provider_service: instance_double(Whatsapp::Providers::WhatsappCloudService),
      provider_config: { 'phone_number_id' => 'phone-id', 'api_key' => 'secret' }
    )
    ownership_checks = 0
    expect(HTTParty).not_to receive(:post)

    described_class.send(
      :send_template_to_whatsapp_api,
      channel,
      '5511999999999',
      { 'name' => 'payment_review', 'language' => { 'code' => 'pt_BR' } },
      ownership_check: -> { (ownership_checks += 1) == 1 }
    )
  end

  context 'when ownership is lost only after the provider accepted the effect' do
    let(:whatsapp_channel) do
      create(
        :channel_whatsapp,
        account: account,
        provider: 'whatsapp_cloud',
        validate_provider_config: false,
        sync_templates: false
      )
    end
    let(:whatsapp_inbox) { whatsapp_channel.inbox }
    let(:whatsapp_conversation) { create(:conversation, account: account, inbox: whatsapp_inbox) }
    let(:whatsapp_message) do
      create(:message, account: account, inbox: whatsapp_inbox, conversation: whatsapp_conversation)
    end

    it 'persists an interactive provider message id without another provider or fallback effect' do
      owned = true
      ownership_check = -> { owned }
      provider = instance_double(Whatsapp::Providers::WhatsappCloudService)
      allow(whatsapp_channel).to receive(:provider_service).and_return(provider)
      expect(provider).to receive(:send_interactive_payload).once do
        owned = false
        'wamid.interactive'
      end
      expect(described_class).not_to receive(:fallback_to_text_message)

      described_class.send(
        :send_interactive_message,
        {
          'type' => 'interactive',
          'interactive' => { 'type' => 'button', 'body' => { 'text' => 'Choose' } }
        },
        whatsapp_message,
        ownership_check: ownership_check
      )

      outgoing = whatsapp_conversation.messages.outgoing.find_by!(content: 'Choose')
      expect(outgoing.source_id).to eq('wamid.interactive')
    end

    it 'persists a template provider message id without another provider or fallback effect' do
      owned = true
      ownership_check = -> { owned }
      provider = instance_double(Whatsapp::Providers::WhatsappCloudService)
      response = instance_double(
        HTTParty::Response,
        code: 200,
        body: '{"messages":[{"id":"wamid.template"}]}',
        success?: true,
        parsed_response: { 'messages' => [{ 'id' => 'wamid.template' }] }
      )
      allow(whatsapp_channel).to receive(:provider_service).and_return(provider)
      expect(HTTParty).to receive(:post).once do
        owned = false
        response
      end
      expect(described_class).not_to receive(:fallback_to_text_message)

      described_class.send(
        :send_template_message,
        {
          'type' => 'template',
          'template' => { 'name' => 'payment_review', 'language' => { 'code' => 'pt_BR' } }
        },
        whatsapp_message,
        ownership_check: ownership_check
      )

      outgoing = whatsapp_conversation.messages.outgoing.find_by!(content: 'Template: payment_review')
      expect(outgoing.source_id).to eq('wamid.template')
    end
  end
end
