require 'rails_helper'

RSpec.describe Integrations::Socialwise::WebhookEnhancerService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation) }
  
  let(:webhook_payload) do
    {
      event: 'message_created',
      message: message,
      conversation: conversation,
      contact: contact,
      inbox: inbox
    }
  end

  describe '.socialwise_active?' do
    context 'when SocialWise hook is not present' do
      it 'returns false' do
        expect(described_class.socialwise_active?(account)).to be false
      end
    end

    context 'when SocialWise hook is disabled' do
      before do
        create(:integrations_hook, 
               app_id: 'socialwise_chatwit', 
               status: 'disabled', 
               account: account,
               settings: { 'enabled' => true })
      end

      it 'returns false' do
        expect(described_class.socialwise_active?(account)).to be false
      end
    end

    context 'when SocialWise hook is enabled but settings disabled' do
      before do
        create(:integrations_hook, 
               app_id: 'socialwise_chatwit', 
               status: 'enabled', 
               account: account,
               settings: { 'enabled' => false })
      end

      it 'returns false' do
        expect(described_class.socialwise_active?(account)).to be false
      end
    end

    context 'when SocialWise hook is enabled and settings enabled as boolean' do
      before do
        create(:integrations_hook, 
               app_id: 'socialwise_chatwit', 
               status: 'enabled', 
               account: account,
               settings: { 'enabled' => true })
      end

      it 'returns true' do
        expect(described_class.socialwise_active?(account)).to be true
      end
    end

    context 'when SocialWise hook is enabled and settings enabled as string' do
      before do
        create(:integrations_hook, 
               app_id: 'socialwise_chatwit', 
               status: 'enabled', 
               account: account,
               settings: { 'enabled' => 'true' })
      end

      it 'returns true' do
        expect(described_class.socialwise_active?(account)).to be true
      end
    end
  end

  describe '.enhance_payload' do
    context 'when SocialWise is not active' do
      it 'returns the original payload unchanged' do
        result = described_class.enhance_payload(webhook_payload, account)
        expect(result).to eq(webhook_payload)
      end
    end

    context 'when SocialWise is active' do
      before do
        create(:integrations_hook, 
               app_id: 'socialwise_chatwit', 
               status: 'enabled', 
               account: account,
               settings: { 'enabled' => true })
      end

      it 'returns enhanced payload with socialwise-chatwit data' do
        result = described_class.enhance_payload(webhook_payload, account)
        
        expect(result).to include('socialwise-chatwit')
        expect(result['socialwise-chatwit']).to be_a(Hash)
        expect(result['socialwise-chatwit']).to include(
          'whatsapp_identifiers',
          'contact_data',
          'conversation_data',
          'message_data',
          'inbox_data',
          'account_data',
          'metadata',
          'whatsapp_api_key'
        )
      end

      it 'includes correct metadata' do
        result = described_class.enhance_payload(webhook_payload, account)
        metadata = result['socialwise-chatwit']['metadata']
        
        expect(metadata['socialwise_active']).to be true
        expect(metadata['payload_version']).to eq('2.0')
        expect(metadata['timestamp']).to be_present
        expect(metadata['has_whatsapp_api_key']).to be false # Default inbox is not WhatsApp
      end

      it 'includes contact data' do
        result = described_class.enhance_payload(webhook_payload, account)
        contact_data = result['socialwise-chatwit']['contact_data']
        
        expect(contact_data['id']).to eq(contact.id)
        expect(contact_data['name']).to eq(contact.name)
        expect(contact_data['custom_attributes']).to be_a(Hash)
      end

      it 'includes conversation data' do
        result = described_class.enhance_payload(webhook_payload, account)
        conversation_data = result['socialwise-chatwit']['conversation_data']
        
        expect(conversation_data['id']).to eq(conversation.id)
        expect(conversation_data['status']).to eq(conversation.status)
      end

      it 'includes message data' do
        result = described_class.enhance_payload(webhook_payload, account)
        message_data = result['socialwise-chatwit']['message_data']
        
        expect(message_data['id']).to eq(message.id)
        expect(message_data['content']).to eq(message.content)
      end

      it 'includes inbox data' do
        result = described_class.enhance_payload(webhook_payload, account)
        inbox_data = result['socialwise-chatwit']['inbox_data']
        
        expect(inbox_data['id']).to eq(inbox.id)
        expect(inbox_data['name']).to eq(inbox.name)
      end

      it 'includes account data' do
        result = described_class.enhance_payload(webhook_payload, account)
        account_data = result['socialwise-chatwit']['account_data']
        
        expect(account_data['id']).to eq(account.id)
        expect(account_data['name']).to eq(account.name)
      end

      it 'includes whatsapp_api_key field' do
        result = described_class.enhance_payload(webhook_payload, account)
        whatsapp_api_key = result['socialwise-chatwit']['whatsapp_api_key']
        
        expect(whatsapp_api_key).to be_nil # Default inbox is not WhatsApp
      end
    end

    context 'when SocialWise is active and inbox is WhatsApp' do
      let(:whatsapp_inbox) { create(:inbox, account: account) }
      let(:whatsapp_channel) { create(:channel_whatsapp, account: account, provider_config: { 'api_key' => 'test_whatsapp_api_key' }) }
      let(:whatsapp_conversation) { create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact) }
      let(:whatsapp_message) { create(:message, account: account, inbox: whatsapp_inbox, conversation: whatsapp_conversation) }
      
      let(:whatsapp_webhook_payload) do
        {
          event: 'message_created',
          message: whatsapp_message,
          conversation: whatsapp_conversation,
          contact: contact,
          inbox: whatsapp_inbox
        }
      end

      before do
        create(:integrations_hook, 
               app_id: 'socialwise_chatwit', 
               status: 'enabled', 
               account: account,
               settings: { 'enabled' => true })
        
        # Associate WhatsApp channel with inbox
        whatsapp_inbox.update!(channel: whatsapp_channel)
      end

      it 'includes WhatsApp API key in the payload' do
        result = described_class.enhance_payload(whatsapp_webhook_payload, account)
        whatsapp_api_key = result['socialwise-chatwit']['whatsapp_api_key']
        
        expect(whatsapp_api_key).to eq('test_whatsapp_api_key')
      end

      it 'indicates WhatsApp API key is present in metadata' do
        result = described_class.enhance_payload(whatsapp_webhook_payload, account)
        metadata = result['socialwise-chatwit']['metadata']
        
        expect(metadata['has_whatsapp_api_key']).to be true
        expect(metadata['is_whatsapp_channel']).to be true
      end

      it 'includes WhatsApp identifiers' do
        result = described_class.enhance_payload(whatsapp_webhook_payload, account)
        whatsapp_identifiers = result['socialwise-chatwit']['whatsapp_identifiers']
        
        expect(whatsapp_identifiers['wamid']).to eq(whatsapp_message.source_id)
        expect(whatsapp_identifiers['whatsapp_id']).to eq(whatsapp_message.source_id)
      end
    end

    context 'when SocialWise is active but WhatsApp channel has no API key' do
      let(:whatsapp_inbox) { create(:inbox, account: account) }
      let(:whatsapp_channel) { create(:channel_whatsapp, account: account, provider_config: {}) }
      let(:whatsapp_conversation) { create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact) }
      let(:whatsapp_message) { create(:message, account: account, inbox: whatsapp_inbox, conversation: whatsapp_conversation) }
      
      let(:whatsapp_webhook_payload) do
        {
          event: 'message_created',
          message: whatsapp_message,
          conversation: whatsapp_conversation,
          contact: contact,
          inbox: whatsapp_inbox
        }
      end

      before do
        create(:integrations_hook, 
               app_id: 'socialwise_chatwit', 
               status: 'enabled', 
               account: account,
               settings: { 'enabled' => true })
        
        # Associate WhatsApp channel with inbox
        whatsapp_inbox.update!(channel: whatsapp_channel)
      end

      it 'includes nil WhatsApp API key in the payload' do
        result = described_class.enhance_payload(whatsapp_webhook_payload, account)
        whatsapp_api_key = result['socialwise-chatwit']['whatsapp_api_key']
        
        expect(whatsapp_api_key).to be_nil
      end

      it 'indicates WhatsApp API key is not present in metadata' do
        result = described_class.enhance_payload(whatsapp_webhook_payload, account)
        metadata = result['socialwise-chatwit']['metadata']
        
        expect(metadata['has_whatsapp_api_key']).to be false
        expect(metadata['is_whatsapp_channel']).to be true
      end
    end
  end
end