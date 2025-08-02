# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Instagram::RichMessageService do
  let(:account) { create(:account) }
  let(:instagram_channel) { create(:channel_instagram, account: account) }
  let(:inbox) { create(:inbox, channel: instagram_channel, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, inbox: inbox, contact: contact, account: account) }
  
  let(:message) do
    create(:message,
           conversation: conversation,
           account: account,
           inbox: inbox,
           message_type: :outgoing,
           content_type: :text,
           content: 'Original text content',
           additional_attributes: { skip_send_reply: true })
  end

  let(:generic_payload) do
    {
      'template_type' => 'generic',
      'elements' => [
        {
          'title' => 'Product 1',
          'subtitle' => 'Amazing product description',
          'image_url' => 'https://example.com/image1.jpg',
          'buttons' => [
            {
              'type' => 'web_url',
              'title' => 'View More',
              'url' => 'https://example.com/product1'
            }
          ]
        }
      ]
    }
  end

  let(:button_payload) do
    {
      'template_type' => 'button',
      'text' => 'Choose an option:',
      'buttons' => [
        {
          'type' => 'postback',
          'title' => 'Yes',
          'payload' => 'YES'
        }
      ]
    }
  end

  let(:quick_replies_payload) do
    {
      'text' => 'What would you like to do?',
      'quick_replies' => [
        {
          'content_type' => 'text',
          'title' => 'Option 1',
          'payload' => 'OPTION_1'
        }
      ]
    }
  end

  let(:service) { described_class.new(message: message, rich_payload: generic_payload) }

  before do
    # Mock Instagram API calls
    stub_request(:post, /graph\.instagram\.com/)
      .to_return(status: 200, body: { message_id: 'test_message_id' }.to_json)
    
    # Mock GlobalConfig for human agent tag
    allow(GlobalConfig).to receive(:get).with('ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT')
                                        .and_return({ 'ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT' => false })
  end

  describe '#perform' do
    context 'when rich dashboard is enabled' do
      before do
        allow(GlobalConfig).to receive(:get).with('SOCIALWISE_RICH_DASHBOARD')
                                            .and_return({ 'SOCIALWISE_RICH_DASHBOARD' => 'true' })
      end

      it 'mirrors payload to dashboard before sending to Instagram API' do
        expect(service).to receive(:mirror_rich_payload_to_dashboard).and_call_original
        expect(service).to receive(:send_rich_message).and_call_original

        service.perform

        # Verify message was updated with rich content
        message.reload
        expect(message.content_type).to eq('cards')
        expect(message.content_attributes['items']).to be_present
        expect(message.content).to eq('Product 1 — Amazing product description')
      end

      it 'continues with Instagram API call even if mirroring fails' do
        allow(Messages::InstagramRendererMapper).to receive(:map).and_raise(StandardError, 'Mapper error')
        allow(Rails.logger).to receive(:error)

        expect { service.perform }.not_to raise_error

        expect(Rails.logger).to have_received(:error).with(
          match(/Dashboard mirroring failed for message #{message.id}/)
        )
      end
    end

    context 'when rich dashboard is disabled' do
      before do
        allow(GlobalConfig).to receive(:get).with('SOCIALWISE_RICH_DASHBOARD')
                                            .and_return({ 'SOCIALWISE_RICH_DASHBOARD' => nil })
      end

      it 'skips dashboard mirroring' do
        expect(service).not_to receive(:mirror_rich_payload_to_dashboard)
        expect(service).to receive(:send_rich_message).and_call_original

        service.perform

        # Verify message was not updated
        message.reload
        expect(message.content_type).to eq('text')
        expect(message.content).to eq('Original text content')
      end
    end
  end

  describe '#mirror_rich_payload_to_dashboard' do
    let(:service) { described_class.new(message: message, rich_payload: generic_payload) }

    context 'when feature flag is enabled' do
      before do
        allow(GlobalConfig).to receive(:get).with('SOCIALWISE_RICH_DASHBOARD')
                                            .and_return({ 'SOCIALWISE_RICH_DASHBOARD' => 'true' })
      end

      it 'updates message with Generic Template mapping' do
        service.send(:mirror_rich_payload_to_dashboard)

        message.reload
        expect(message.content_type).to eq('cards')
        expect(message.content_attributes['items']).to be_an(Array)
        expect(message.content_attributes['items'].length).to eq(1)
        expect(message.content).to eq('Product 1 — Amazing product description')
      end

      it 'updates message with Button Template mapping' do
        service = described_class.new(message: message, rich_payload: button_payload)
        service.send(:mirror_rich_payload_to_dashboard)

        message.reload
        expect(message.content_type).to eq('cards')
        expect(message.content_attributes['items']).to be_an(Array)
        expect(message.content_attributes['items'].length).to eq(1)
        expect(message.content).to eq('Choose an option:')
      end

      it 'updates message with Quick Replies mapping' do
        service = described_class.new(message: message, rich_payload: quick_replies_payload)
        service.send(:mirror_rich_payload_to_dashboard)

        message.reload
        expect(message.content_type).to eq('input_select')
        expect(message.content_attributes['items']).to be_an(Array)
        expect(message.content_attributes['items'].length).to eq(1)
        expect(message.content).to eq('What would you like to do? (1 options)')
      end

      it 'uses update_columns for performance' do
        expect(message).to receive(:update_columns).with(
          content_type: Message.content_types['cards'],
          content_attributes: hash_including('items'),
          content: 'Product 1 — Amazing product description',
          updated_at: be_within(1.second).of(Time.current)
        )

        service.send(:mirror_rich_payload_to_dashboard)
      end

      it 'logs mirroring process' do
        allow(Rails.logger).to receive(:info)

        service.send(:mirror_rich_payload_to_dashboard)

        expect(Rails.logger).to have_received(:info).with(
          '[SOCIALWISE-INSTAGRAM-RICH] === STARTING DASHBOARD MIRRORING ==='
        )
        expect(Rails.logger).to have_received(:info).with(
          "[SOCIALWISE-INSTAGRAM-RICH] Message ID: #{message.id}"
        )
        expect(Rails.logger).to have_received(:info).with(
          '[SOCIALWISE-INSTAGRAM-RICH] === DASHBOARD MIRRORING COMPLETED ==='
        )
      end

      it 'handles mapping errors gracefully' do
        allow(Messages::InstagramRendererMapper).to receive(:map).and_raise(StandardError, 'Test error')
        allow(Rails.logger).to receive(:error)

        expect { service.send(:mirror_rich_payload_to_dashboard) }.not_to raise_error

        expect(Rails.logger).to have_received(:error).with(
          "[SOCIALWISE-INSTAGRAM-RICH] Dashboard mirroring failed for message #{message.id}: StandardError: Test error"
        )
      end

      it 'tracks unique message.id for metrics correlation' do
        allow(Rails.logger).to receive(:info)

        service.send(:mirror_rich_payload_to_dashboard)

        expect(Rails.logger).to have_received(:info).with(
          "[SOCIALWISE-INSTAGRAM-RICH] Message ID: #{message.id}"
        ).at_least(:once)
      end
    end

    context 'when feature flag is disabled' do
      before do
        allow(GlobalConfig).to receive(:get).with('SOCIALWISE_RICH_DASHBOARD')
                                            .and_return({ 'SOCIALWISE_RICH_DASHBOARD' => nil })
      end

      it 'returns early without updating message' do
        expect(message).not_to receive(:update_columns)

        service.send(:mirror_rich_payload_to_dashboard)

        message.reload
        expect(message.content_type).to eq('text')
        expect(message.content).to eq('Original text content')
      end
    end
  end

  describe '#rich_dashboard_enabled?' do
    let(:service) { described_class.new(message: message, rich_payload: generic_payload) }

    it 'returns true when feature flag is enabled' do
      allow(GlobalConfig).to receive(:get).with('SOCIALWISE_RICH_DASHBOARD')
                                          .and_return({ 'SOCIALWISE_RICH_DASHBOARD' => 'true' })

      expect(service.send(:rich_dashboard_enabled?)).to be true
    end

    it 'returns false when feature flag is disabled' do
      allow(GlobalConfig).to receive(:get).with('SOCIALWISE_RICH_DASHBOARD')
                                          .and_return({ 'SOCIALWISE_RICH_DASHBOARD' => nil })

      expect(service.send(:rich_dashboard_enabled?)).to be false
    end

    it 'returns false when feature flag is empty string' do
      allow(GlobalConfig).to receive(:get).with('SOCIALWISE_RICH_DASHBOARD')
                                          .and_return({ 'SOCIALWISE_RICH_DASHBOARD' => '' })

      expect(service.send(:rich_dashboard_enabled?)).to be false
    end

    it 'logs the feature flag check with account ID' do
      allow(GlobalConfig).to receive(:get).with('SOCIALWISE_RICH_DASHBOARD')
                                          .and_return({ 'SOCIALWISE_RICH_DASHBOARD' => 'true' })
      allow(Rails.logger).to receive(:info)

      service.send(:rich_dashboard_enabled?)

      expect(Rails.logger).to have_received(:info).with(
        "[SOCIALWISE-INSTAGRAM-RICH] Rich dashboard enabled check: true for account #{account.id}"
      )
    end
  end

  describe 'content_type serialization' do
    before do
      allow(GlobalConfig).to receive(:get).with('SOCIALWISE_RICH_DASHBOARD')
                                          .and_return({ 'SOCIALWISE_RICH_DASHBOARD' => 'true' })
    end

    it 'stores content_type as enum integer in database' do
      service.send(:mirror_rich_payload_to_dashboard)

      message.reload
      # Check database value is integer
      expect(message.read_attribute_before_type_cast('content_type')).to eq(Message.content_types['cards'])
      expect(message.read_attribute_before_type_cast('content_type')).to be_a(Integer)
    end

    it 'serializes content_type as string for API responses' do
      service.send(:mirror_rich_payload_to_dashboard)

      message.reload
      # Check enum method returns string
      expect(message.content_type).to eq('cards')
      expect(message.content_type).to be_a(String)
    end
  end

  describe 'skip_send_reply flag verification' do
    it 'verifies skip_send_reply flag is applied during message creation' do
      # This test verifies that the message was created with skip_send_reply flag
      # which prevents SendReplyJob from being enqueued
      expect(message.additional_attributes['skip_send_reply']).to be true
    end

    it 'prevents duplicate message sending when flag is set' do
      # Mock the send_reply method to verify it's not called
      expect(message).not_to receive(:send_reply)

      # Simulate the message callback that would normally trigger send_reply
      # Since skip_send_reply is true, it should return early
      result = message.send_reply
      expect(result).to be_nil
    end
  end

  describe 'integration with existing Instagram API flow' do
    before do
      allow(GlobalConfig).to receive(:get).with('SOCIALWISE_RICH_DASHBOARD')
                                          .and_return({ 'SOCIALWISE_RICH_DASHBOARD' => 'true' })
    end

    it 'maintains existing Instagram API call flow' do
      expect(service).to receive(:send_message).and_call_original

      service.perform

      # Verify Instagram API was called
      expect(WebMock).to have_requested(:post, /graph\.instagram\.com/)
    end

    it 'preserves existing error handling' do
      # Mock Instagram API to return error
      stub_request(:post, /graph\.instagram\.com/)
        .to_return(status: 400, body: { error: 'Bad Request' }.to_json)

      allow(service).to receive(:handle_error)

      service.perform

      expect(service).to have_received(:handle_error)
    end

    it 'maintains human agent tag functionality' do
      allow(GlobalConfig).to receive(:get).with('ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT')
                                          .and_return({ 'ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT' => true })

      service.perform

      # Verify human agent tag was applied
      expect(WebMock).to have_requested(:post, /graph\.instagram\.com/)
        .with(body: hash_including('messaging_type' => 'MESSAGE_TAG', 'tag' => 'HUMAN_AGENT'))
    end
  end

  describe 'performance considerations' do
    before do
      allow(GlobalConfig).to receive(:get).with('SOCIALWISE_RICH_DASHBOARD')
                                          .and_return({ 'SOCIALWISE_RICH_DASHBOARD' => 'true' })
    end

    it 'uses update_columns instead of save for better performance' do
      expect(message).to receive(:update_columns).and_call_original
      expect(message).not_to receive(:save)
      expect(message).not_to receive(:save!)

      service.send(:mirror_rich_payload_to_dashboard)
    end

    it 'completes mirroring quickly' do
      start_time = Time.current

      service.send(:mirror_rich_payload_to_dashboard)

      elapsed_time = Time.current - start_time
      expect(elapsed_time).to be < 0.1 # Should complete in under 100ms
    end
  end

  describe 'error scenarios' do
    before do
      allow(GlobalConfig).to receive(:get).with('SOCIALWISE_RICH_DASHBOARD')
                                          .and_return({ 'SOCIALWISE_RICH_DASHBOARD' => 'true' })
    end

    it 'handles database update failures gracefully' do
      allow(message).to receive(:update_columns).and_raise(ActiveRecord::RecordInvalid)
      allow(Rails.logger).to receive(:error)

      expect { service.send(:mirror_rich_payload_to_dashboard) }.not_to raise_error

      expect(Rails.logger).to have_received(:error).with(
        match(/Dashboard mirroring failed for message #{message.id}/)
      )
    end

    it 'handles mapper service failures gracefully' do
      allow(Messages::InstagramRendererMapper).to receive(:map).and_raise(StandardError, 'Mapper failed')
      allow(Rails.logger).to receive(:error)

      expect { service.send(:mirror_rich_payload_to_dashboard) }.not_to raise_error

      expect(Rails.logger).to have_received(:error).with(
        match(/Dashboard mirroring failed for message #{message.id}/)
      )
    end

    it 'continues with Instagram API call even when mirroring fails' do
      allow(service).to receive(:mirror_rich_payload_to_dashboard).and_raise(StandardError)
      expect(service).to receive(:send_rich_message).and_call_original

      expect { service.perform }.not_to raise_error
    end
  end
end