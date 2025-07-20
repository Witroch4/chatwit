require 'rails_helper'

RSpec.describe Integrations::Dialogflow::ProcessorService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation) }
  let(:hook) { create(:integrations_hook, app_id: 'dialogflow', account: account) }
  
  let(:event_data) do
    {
      message: message,
      conversation: conversation,
      contact: contact,
      inbox: inbox
    }
  end

  let(:service) { described_class.new(event_data: event_data, hook: hook) }

  describe '#build_whatsapp_payload_data' do
    context 'when inbox is not WhatsApp channel' do
      it 'returns payload without WhatsApp API key' do
        result = service.send(:build_whatsapp_payload_data)
        
        expect(result['whatsapp_api_key']).to be_nil
        expect(result['has_whatsapp_api_key']).to be false
        expect(result['is_whatsapp_channel']).to be false
      end

      it 'includes basic payload structure' do
        result = service.send(:build_whatsapp_payload_data)
        
        expect(result).to include(
          'wamid',
          'whatsapp_id',
          'contact_name',
          'contact_phone',
          'conversation_id',
          'inbox_id',
          'message_id',
          'socialwise_active'
        )
      end
    end

    context 'when inbox is WhatsApp channel with API key' do
      let(:whatsapp_channel) { create(:channel_whatsapp, account: account, provider_config: { 'api_key' => 'test_whatsapp_api_key_123' }) }
      let(:whatsapp_inbox) { create(:inbox, account: account, channel: whatsapp_channel) }
      let(:whatsapp_conversation) { create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact) }
      let(:whatsapp_message) { create(:message, account: account, inbox: whatsapp_inbox, conversation: whatsapp_conversation) }
      
      let(:whatsapp_event_data) do
        {
          message: whatsapp_message,
          conversation: whatsapp_conversation,
          contact: contact,
          inbox: whatsapp_inbox
        }
      end

      let(:whatsapp_service) { described_class.new(event_data: whatsapp_event_data, hook: hook) }

      it 'includes WhatsApp API key in the payload' do
        result = whatsapp_service.send(:build_whatsapp_payload_data)
        
        expect(result['whatsapp_api_key']).to eq('test_whatsapp_api_key_123')
        expect(result['has_whatsapp_api_key']).to be true
        expect(result['is_whatsapp_channel']).to be true
      end

      it 'includes WhatsApp identifiers' do
        result = whatsapp_service.send(:build_whatsapp_payload_data)
        
        expect(result['wamid']).to eq(whatsapp_message.source_id)
        expect(result['whatsapp_id']).to eq(whatsapp_message.source_id)
      end

      it 'includes complete payload structure' do
        result = whatsapp_service.send(:build_whatsapp_payload_data)
        
        expect(result).to include(
          'wamid',
          'whatsapp_id',
          'contact_name',
          'contact_phone',
          'conversation_id',
          'inbox_id',
          'message_id',
          'whatsapp_api_key',
          'has_whatsapp_api_key',
          'is_whatsapp_channel',
          'socialwise_active',
          'payload_version'
        )
      end
    end

    context 'when inbox is WhatsApp channel without API key' do
      let(:whatsapp_channel) { create(:channel_whatsapp, account: account, provider_config: {}) }
      let(:whatsapp_inbox) { create(:inbox, account: account, channel: whatsapp_channel) }
      let(:whatsapp_conversation) { create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact) }
      let(:whatsapp_message) { create(:message, account: account, inbox: whatsapp_inbox, conversation: whatsapp_conversation) }
      
      let(:whatsapp_event_data) do
        {
          message: whatsapp_message,
          conversation: whatsapp_conversation,
          contact: contact,
          inbox: whatsapp_inbox
        }
      end

      let(:whatsapp_service) { described_class.new(event_data: whatsapp_event_data, hook: hook) }

      it 'includes nil WhatsApp API key in the payload' do
        result = whatsapp_service.send(:build_whatsapp_payload_data)
        
        expect(result['whatsapp_api_key']).to be_nil
        expect(result['has_whatsapp_api_key']).to be false
        expect(result['is_whatsapp_channel']).to be true
      end
    end

    context 'when WhatsApp channel has provider_config but no api_key' do
      let(:whatsapp_channel) { create(:channel_whatsapp, account: account, provider_config: { 'other_key' => 'other_value' }) }
      let(:whatsapp_inbox) { create(:inbox, account: account, channel: whatsapp_channel) }
      let(:whatsapp_conversation) { create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact) }
      let(:whatsapp_message) { create(:message, account: account, inbox: whatsapp_inbox, conversation: whatsapp_conversation) }
      
      let(:whatsapp_event_data) do
        {
          message: whatsapp_message,
          conversation: whatsapp_conversation,
          contact: contact,
          inbox: whatsapp_inbox
        }
      end

      let(:whatsapp_service) { described_class.new(event_data: whatsapp_event_data, hook: hook) }

      it 'includes nil WhatsApp API key in the payload' do
        result = whatsapp_service.send(:build_whatsapp_payload_data)
        
        expect(result['whatsapp_api_key']).to be_nil
        expect(result['has_whatsapp_api_key']).to be false
      end
    end

    context 'when an error occurs during API key extraction' do
      let(:whatsapp_channel) { create(:channel_whatsapp, account: account, provider_config: { 'api_key' => 'test_key' }) }
      let(:whatsapp_inbox) { create(:inbox, account: account, channel: whatsapp_channel) }
      let(:whatsapp_conversation) { create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact) }
      let(:whatsapp_message) { create(:message, account: account, inbox: whatsapp_inbox, conversation: whatsapp_conversation) }
      
      let(:whatsapp_event_data) do
        {
          message: whatsapp_message,
          conversation: whatsapp_conversation,
          contact: contact,
          inbox: whatsapp_inbox
        }
      end

      let(:whatsapp_service) { described_class.new(event_data: whatsapp_event_data, hook: hook) }

      before do
        # Mock an error when accessing provider_config
        allow(whatsapp_inbox.channel).to receive(:provider_config).and_raise(StandardError, 'Provider config error')
      end

      it 'handles the error gracefully and includes error information in fallback payload' do
        result = whatsapp_service.send(:build_whatsapp_payload_data)
        
        expect(result['whatsapp_api_key']).to be_nil
        expect(result['has_whatsapp_api_key']).to be false
        expect(result['error']).to include('Payload construction failed')
      end
    end
  end
end
