require 'rails_helper'

RSpec.describe SendReplyJob do
  subject(:job) { described_class.perform_later(message) }

  let(:message) { create(:message) }

  it 'enqueues the job' do
    expect { job }.to have_enqueued_job(described_class)
      .with(message)
      .on_queue('high')
  end

  context 'when the job is triggered on a new message' do
    let(:process_service) { double }

    before do
      allow(process_service).to receive(:perform)
    end

    def expect_mapped_service_to_perform(message, service_class_name)
      channel_name = message.conversation.inbox.channel.class.name
      service_class = described_class::CHANNEL_SERVICES.fetch(channel_name)

      expect(service_class.name).to eq(service_class_name)
      expect(service_class).to receive(:new).with(message: message).and_return(process_service)
      expect(process_service).to receive(:perform)

      described_class.perform_now(message.id)
    end

    it 'calls Facebook::SendOnFacebookService when its facebook message' do
      stub_request(:post, /graph.facebook.com/)
      facebook_channel = create(:channel_facebook_page)
      facebook_inbox = create(:inbox, channel: facebook_channel)
      message = create(:message, conversation: create(:conversation, inbox: facebook_inbox))
      allow(Facebook::SendOnFacebookService).to receive(:new).with(message: message).and_return(process_service)
      expect(Facebook::SendOnFacebookService).to receive(:new).with(message: message)
      expect(process_service).to receive(:perform)
      described_class.perform_now(message.id)
    end

    it 'calls ::Twitter::SendOnTwitterService when its twitter message' do
      twitter_channel = create(:channel_twitter_profile)
      twitter_inbox = create(:inbox, channel: twitter_channel)
      message = create(:message, conversation: create(:conversation, inbox: twitter_inbox))
      expect_mapped_service_to_perform(message, 'Twitter::SendOnTwitterService')
    end

    it 'calls ::Twilio::SendOnTwilioService when its twilio message' do
      twilio_channel = create(:channel_twilio_sms)
      message = create(:message, conversation: create(:conversation, inbox: twilio_channel.inbox))
      expect_mapped_service_to_perform(message, 'Twilio::SendOnTwilioService')
    end

    it 'calls ::Telegram::SendOnTelegramService when its telegram message' do
      telegram_channel = create(:channel_telegram)
      message = create(:message, conversation: create(:conversation, inbox: telegram_channel.inbox))
      expect_mapped_service_to_perform(message, 'Telegram::SendOnTelegramService')
    end

    it 'calls ::Line:SendOnLineService when its line message' do
      line_channel = create(:channel_line)
      message = create(:message, conversation: create(:conversation, inbox: line_channel.inbox))
      expect_mapped_service_to_perform(message, 'Line::SendOnLineService')
    end

    it 'calls ::Whatsapp:SendOnWhatsappService when its whatsapp message' do
      stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
      whatsapp_channel = create(:channel_whatsapp, sync_templates: false)
      message = create(:message, conversation: create(:conversation, inbox: whatsapp_channel.inbox))
      expect_mapped_service_to_perform(message, 'Whatsapp::SendOnWhatsappService')
    end

    it 'calls ::Sms::SendOnSmsService when its sms message' do
      sms_channel = create(:channel_sms)
      message = create(:message, conversation: create(:conversation, inbox: sms_channel.inbox))
      expect_mapped_service_to_perform(message, 'Sms::SendOnSmsService')
    end

    it 'calls ::Instagram::Direct::SendOnInstagramService when its instagram message' do
      instagram_channel = create(:channel_instagram)
      message = create(:message, conversation: create(:conversation, inbox: instagram_channel.inbox))
      expect_mapped_service_to_perform(message, 'Instagram::SendOnInstagramService')
    end

    it 'calls ::Instagram::Messenger::SendOnInstagramService when its an instagram_direct_message from facebook channel' do
      stub_request(:post, /graph.facebook.com/)
      facebook_channel = create(:channel_facebook_page)
      facebook_inbox = create(:inbox, channel: facebook_channel)
      conversation = create(:conversation,
                            inbox: facebook_inbox,
                            additional_attributes: { 'type' => 'instagram_direct_message' })
      message = create(:message, conversation: conversation)

      allow(Instagram::Messenger::SendOnInstagramService).to receive(:new).with(message: message).and_return(process_service)
      expect(Instagram::Messenger::SendOnInstagramService).to receive(:new).with(message: message)
      expect(process_service).to receive(:perform)
      described_class.perform_now(message.id)
    end

    it 'calls ::Email::SendOnEmailService when its email message' do
      email_channel = create(:channel_email)
      message = create(:message, conversation: create(:conversation, inbox: email_channel.inbox))
      expect_mapped_service_to_perform(message, 'Email::SendOnEmailService')
    end

    it 'calls ::Messages::SendEmailNotificationService when its webwidget message' do
      webwidget_channel = create(:channel_widget)
      message = create(:message, conversation: create(:conversation, inbox: webwidget_channel.inbox))
      expect_mapped_service_to_perform(message, 'Messages::SendEmailNotificationService')
    end

    it 'calls ::Messages::SendEmailNotificationService when its api channel message' do
      api_channel = create(:channel_api)
      message = create(:message, conversation: create(:conversation, inbox: api_channel.inbox))
      expect_mapped_service_to_perform(message, 'Messages::SendEmailNotificationService')
    end

    it 'calls ::Tiktok::SendOnTiktokService when its tiktok message' do
      tiktok_channel = create(:channel_tiktok)
      message = create(:message, conversation: create(:conversation, inbox: tiktok_channel.inbox))
      expect_mapped_service_to_perform(message, 'Tiktok::SendOnTiktokService')
    end
  end

  # Anti-regressao (2026-08-03, inbox 108 / flow "Mandado de Seguranca"):
  # o SocialWise Flow no caminho async cria a mensagem interativa via REST. Sem este
  # roteamento, Instagram/Facebook caem no send service padrao, que monta apenas
  # `message: { text: ... }` — a mensagem chega ao lead sem nenhum botao, com HTTP 200.
  context 'with an async SocialWise Flow interactive message' do
    let(:rich_service) { instance_double(Instagram::RichMessageService, perform: nil) }
    let(:meta_interactive) do
      {
        'message_format' => 'QUICK_REPLIES',
        'text' => 'Duvidas sobre o Mandado de Seguranca?',
        'quick_replies' => [
          { 'content_type' => 'text', 'title' => 'Falar com a Dra', 'payload' => 'flow_qr_1' }
        ]
      }
    end

    it 'routes an Instagram message with a meta payload to the rich message service' do
      instagram_channel = create(:channel_instagram)
      message = create(:message,
                       conversation: create(:conversation, inbox: instagram_channel.inbox),
                       message_type: :outgoing,
                       content_type: :integrations,
                       content_attributes: { 'meta_interactive' => meta_interactive })

      allow(Instagram::RichMessageService).to receive(:new)
        .with(message: message, rich_payload: meta_interactive).and_return(rich_service)
      expect(Instagram::SendOnInstagramService).not_to receive(:new)

      described_class.perform_now(message.id)

      expect(rich_service).to have_received(:perform)
    end

    it 'keeps the plain send service when there is no meta payload' do
      instagram_channel = create(:channel_instagram)
      message = create(:message,
                       conversation: create(:conversation, inbox: instagram_channel.inbox),
                       message_type: :outgoing)
      plain_service = instance_double(Instagram::SendOnInstagramService, perform: nil)

      allow(Instagram::SendOnInstagramService).to receive(:new).with(message: message).and_return(plain_service)
      expect(Instagram::RichMessageService).not_to receive(:new)

      described_class.perform_now(message.id)

      expect(plain_service).to have_received(:perform)
    end

    it 'leaves WhatsApp on its own provider path' do
      channel = create(:channel_whatsapp, sync_templates: false, validate_provider_config: false)
      message = create(:message,
                       conversation: create(:conversation, inbox: channel.inbox),
                       message_type: :outgoing,
                       content_type: :integrations,
                       content_attributes: { 'interactive' => { 'type' => 'button' } })
      whatsapp_service = instance_double(Whatsapp::SendOnWhatsappService, perform: nil)

      allow(Whatsapp::SendOnWhatsappService).to receive(:new).with(message: message).and_return(whatsapp_service)

      described_class.perform_now(message.id)

      expect(whatsapp_service).to have_received(:perform)
    end
  end

  context 'with the Socialwise ownership permit fence' do
    let(:whatsapp_service) { instance_double(Whatsapp::SendOnWhatsappService, perform: nil) }
    let(:channel) { create(:channel_whatsapp, sync_templates: false, validate_provider_config: false) }
    let(:conversation) { create(:conversation, inbox: channel.inbox) }

    before do
      allow(Whatsapp::SendOnWhatsappService).to receive(:new).and_return(whatsapp_service)
    end

    def fenced_message(epoch)
      create(:message, conversation: conversation, message_type: :outgoing,
                       additional_attributes: { 'socialwise_ownership_epoch' => epoch })
    end

    it 'delivers a message that carries no ownership marker' do
      message = create(:message, conversation: conversation, message_type: :outgoing)

      described_class.perform_now(message.id)

      expect(whatsapp_service).to have_received(:perform)
    end

    it 'stops a stale owner delivery before the provider when ownership moved to phase 2' do
      message = fenced_message(1)
      Integrations::SocialwiseFlow::OwnershipGuard.new(conversation).pause_for_phase2!

      described_class.perform_now(message.id)

      expect(whatsapp_service).not_to have_received(:perform)
    end

    it 'delivers when the message epoch still matches the current owner' do
      guard = Integrations::SocialwiseFlow::OwnershipGuard.new(conversation)
      message = fenced_message(guard.snapshot_epoch)

      described_class.perform_now(message.id)

      expect(whatsapp_service).to have_received(:perform)
    end
  end
end
