# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Socialwise::InstagramResponseProcessor do
  let(:account) { create(:account) }
  let(:instagram_channel) { create(:channel_instagram, account: account) }
  let(:inbox) { create(:inbox, channel: instagram_channel, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation) }

  describe '.process' do
    context 'with Button Template payload' do
      let(:button_template_payload) do
        {
          'message_format' => 'BUTTON_TEMPLATE',
          'payload' => {
            'template_type' => 'button',
            'text' => 'Choose an option:',
            'buttons' => [
              {
                'type' => 'postback',
                'title' => 'Option 1',
                'payload' => 'option_1'
              },
              {
                'type' => 'web_url',
                'title' => 'Visit Website',
                'url' => 'https://example.com'
              }
            ]
          }
        }
      end

      it 'processes Button Template successfully' do
        # Mock the Instagram Rich Message Service
        rich_message_service = instance_double(Instagram::RichMessageService)
        allow(Instagram::RichMessageService).to receive(:new).and_return(rich_message_service)
        allow(rich_message_service).to receive(:perform)

        result = described_class.process(button_template_payload, message)

        expect(result).to be true
        expect(Instagram::RichMessageService).to have_received(:new).with(
          message: message,
          rich_payload: hash_including(
            'template_type' => 'button',
            'text' => 'Choose an option:',
            'buttons' => array_including(
              hash_including('type' => 'postback', 'title' => 'Option 1', 'payload' => 'option_1'),
              hash_including('type' => 'web_url', 'title' => 'Visit Website', 'url' => 'https://example.com')
            )
          )
        )
        expect(rich_message_service).to have_received(:perform)
      end

      it 'validates Button Template payload structure' do
        invalid_payload = {
          'message_format' => 'BUTTON_TEMPLATE',
          'payload' => {
            'template_type' => 'button'
            # Missing required 'text' and 'buttons'
          }
        }

        # Should fallback to text message when validation fails
        expect(conversation.messages).to receive(:create!).with(
          hash_including(
            content: 'Message received',
            message_type: :outgoing
          )
        )

        result = described_class.process(invalid_payload, message)
        expect(result).to be true # Returns true even on fallback
      end

      it 'handles Instagram Rich Message Service errors gracefully' do
        # Mock the service to raise an error
        rich_message_service = instance_double(Instagram::RichMessageService)
        allow(Instagram::RichMessageService).to receive(:new).and_return(rich_message_service)
        allow(rich_message_service).to receive(:perform).and_raise(StandardError, 'API Error')

        # Should fallback to text message when service fails
        expect(conversation.messages).to receive(:create!).with(
          hash_including(
            content: 'Choose an option:',
            message_type: :outgoing
          )
        )

        result = described_class.process(button_template_payload, message)
        expect(result).to be true # Returns true even on fallback
      end
    end

    context 'with non-Instagram channel' do
      let(:web_widget_channel) { create(:channel_web_widget, account: account) }
      let(:web_inbox) { create(:inbox, channel: web_widget_channel, account: account) }
      let(:web_conversation) { create(:conversation, account: account, inbox: web_inbox, contact: contact) }
      let(:web_message) { create(:message, account: account, inbox: web_inbox, conversation: web_conversation) }

      let(:button_template_payload) do
        {
          'message_format' => 'BUTTON_TEMPLATE',
          'payload' => {
            'template_type' => 'button',
            'text' => 'Choose an option:',
            'buttons' => [
              {
                'type' => 'postback',
                'title' => 'Option 1',
                'payload' => 'option_1'
              }
            ]
          }
        }
      end

      it 'falls back to text message for non-Instagram channels' do
        # Should fallback to text message for non-Instagram channels
        expect(web_conversation.messages).to receive(:create!).with(
          hash_including(
            content: 'Choose an option:',
            message_type: :outgoing
          )
        )

        result = described_class.process(button_template_payload, web_message)
        expect(result).to be true
      end
    end
  end

  describe '.validate_button_template' do
    it 'validates valid Button Template payload' do
      valid_payload = {
        'template_type' => 'button',
        'text' => 'Choose an option:',
        'buttons' => [
          {
            'type' => 'postback',
            'title' => 'Option 1',
            'payload' => 'option_1'
          }
        ]
      }

      result = described_class.send(:validate_button_template, valid_payload)
      expect(result).to be true
    end

    it 'rejects Button Template with missing text' do
      invalid_payload = {
        'template_type' => 'button',
        'buttons' => [
          {
            'type' => 'postback',
            'title' => 'Option 1',
            'payload' => 'option_1'
          }
        ]
      }

      result = described_class.send(:validate_button_template, invalid_payload)
      expect(result).to be false
    end

    it 'rejects Button Template with too many buttons' do
      invalid_payload = {
        'template_type' => 'button',
        'text' => 'Choose an option:',
        'buttons' => [
          { 'type' => 'postback', 'title' => 'Option 1', 'payload' => 'option_1' },
          { 'type' => 'postback', 'title' => 'Option 2', 'payload' => 'option_2' },
          { 'type' => 'postback', 'title' => 'Option 3', 'payload' => 'option_3' },
          { 'type' => 'postback', 'title' => 'Option 4', 'payload' => 'option_4' } # Too many
        ]
      }

      result = described_class.send(:validate_button_template, invalid_payload)
      expect(result).to be false
    end
  end

  describe '.build_button_template_payload' do
    it 'builds Instagram API compatible payload' do
      original_payload = {
        'template_type' => 'button',
        'text' => 'Choose an option:',
        'buttons' => [
          {
            'type' => 'postback',
            'title' => 'Option 1',
            'payload' => 'option_1'
          },
          {
            'type' => 'web_url',
            'title' => 'Visit Website',
            'url' => 'https://example.com'
          }
        ]
      }

      result = described_class.send(:build_button_template_payload, original_payload)

      expect(result).to eq({
        'template_type' => 'button',
        'text' => 'Choose an option:',
        'buttons' => [
          {
            'type' => 'postback',
            'title' => 'Option 1',
            'payload' => 'option_1'
          },
          {
            'type' => 'web_url',
            'title' => 'Visit Website',
            'url' => 'https://example.com'
          }
        ]
      })
    end
  end
end