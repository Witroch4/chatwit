require 'rails_helper'

RSpec.describe Integrations::SocialwiseFlow::ProcessorService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:hook) do
    create(
      :integrations_hook,
      inbox: inbox,
      account: account,
      app_id: 'socialwise_flow',
      settings: { 'language' => 'pt-BR' }
    )
  end
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :open) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation) }
  let(:service) { described_class.new(event_name: 'message.created', hook: hook, event_data: { message: message }) }
  let(:instagram_payload_without_format) do
    {
      'text' => 'Olá! Sou a Ana e posso ajudar. Escolha uma opção:',
      'quick_replies' => [
        { 'content_type' => 'text', 'title' => 'Mandado OAB', 'payload' => '@mandado-de-seguranca-oab' }
      ]
    }
  end
  let(:button_payload_with_wrong_format) do
    {
      'message_format' => 'QUICK_REPLIES',
      'template_type' => 'button',
      'text' => 'Escolha uma opção:',
      'buttons' => [
        { 'type' => 'postback', 'title' => 'Falar com atendente', 'payload' => '@falar_atendente' }
      ]
    }
  end

  def create_eligible_trigger
    create(:captain_payment_review_trigger, conversation: conversation, account: account, state: :eligible)
  end

  describe '#perform ownership fence' do
    it 'stops before typing, Redis, enqueue, or HTTP when Captain has an eligible trigger' do
      create_eligible_trigger

      expect(service).not_to receive(:send_typing_indicator_to_user)
      expect(Redis::Alfred).not_to receive(:get)
      expect(Redis::Alfred).not_to receive(:set)
      expect(Redis::Alfred).not_to receive(:lpush)
      expect(Redis::Alfred).not_to receive(:delete)
      expect(SocialwiseDebounceJob).not_to receive(:perform_later)
      expect(HTTParty).not_to receive(:post)

      service.perform
    end

    it 'allows an ineligible trigger to continue through the normal ingress' do
      create(:captain_payment_review_trigger, conversation: conversation, account: account, state: :ineligible)
      allow(service).to receive(:send_typing_indicator_to_user)
      expect(service).to receive(:process_content).with(message)

      service.perform
    end

    it 'revalidates before writing debounce state or scheduling a job' do
      allow(service).to receive(:send_typing_indicator_to_user) { create_eligible_trigger }
      expect(Redis::Alfred).not_to receive(:lpush)
      expect(Redis::Alfred).not_to receive(:set)
      expect(SocialwiseDebounceJob).not_to receive(:perform_later)

      with_modified_env(SOCIALWISE_DEBOUNCE_MS: '5000') { service.perform }
    end

    it 'stores and schedules the immutable ingress epoch with a debounced message', :aggregate_failures do
      conversation.update!(additional_attributes: { 'socialwise_ownership_epoch' => 7 })
      buffered_payload = nil
      enqueued_arguments = nil
      redis_connection = instance_double(Redis, expire: true)

      allow(service).to receive(:send_typing_indicator_to_user)
      allow(Redis::Alfred).to receive(:lpush) { |_key, value| buffered_payload = JSON.parse(value) }
      allow(Redis::Alfred).to receive(:get).and_return(nil)
      allow(Redis::Alfred).to receive(:set).and_return(true)
      # rubocop:disable Style/GlobalVars
      allow($alfred).to receive(:with).and_yield(redis_connection)
      # rubocop:enable Style/GlobalVars
      allow(SocialwiseDebounceJob).to receive(:perform_later) { |*arguments| enqueued_arguments = arguments }

      with_modified_env(SOCIALWISE_DEBOUNCE_MS: '5000') { service.perform }

      expect(buffered_payload).to include('message_id' => message.id, 'ownership_epoch' => 7)
      expect(enqueued_arguments).to eq([conversation.id, hook.id, 'message.created', 5000, 30_000, 7])
    end

    it 'still records a human takeover and clears debounce while bot publications are fenced', :aggregate_failures do
      conversation.update!(status: :pending)
      agent_reply = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        sender: create(:user, account: account)
      )
      create_eligible_trigger
      human_service = described_class.new(event_name: 'message.created', hook: hook, event_data: { message: agent_reply })
      messages_key = format(Redis::Alfred::SOCIALWISE_DEBOUNCE_MESSAGES, conversation_id: conversation.id)
      first_at_key = format(Redis::Alfred::SOCIALWISE_DEBOUNCE_FIRST_AT, conversation_id: conversation.id)
      last_at_key = format(Redis::Alfred::SOCIALWISE_DEBOUNCE_LAST_AT, conversation_id: conversation.id)
      allow(Redis::Alfred).to receive(:lrange).and_return([])
      allow(Redis::Alfred).to receive(:lrange).with(messages_key, 0, -1).and_return(['pending'])
      expect(Redis::Alfred).to receive(:delete).with(messages_key)
      expect(Redis::Alfred).to receive(:delete).with(first_at_key)
      expect(Redis::Alfred).to receive(:delete).with(last_at_key)
      expect(human_service).not_to receive(:send_typing_indicator_to_user)
      expect(SocialwiseDebounceJob).not_to receive(:perform_later)
      expect(HTTParty).not_to receive(:post)

      human_service.perform

      expect(conversation.reload).to be_open
      expect(conversation.additional_attributes['socialwise_handoff_by']).to eq('agent_reply')
    end
  end

  describe '#process_content ownership fence' do
    let(:http_response) { instance_double(HTTParty::Response, success?: true, parsed_response: { 'text' => 'late response' }) }

    before do
      allow(service).to receive(:send_typing_indicator_to_user)
    end

    it 'drops the response when a trigger appears during the Socialwise HTTP call' do
      allow(HTTParty).to receive(:post) do
        create_eligible_trigger
        http_response
      end
      expect(service).not_to receive(:create_conversation)

      service.perform
    end

    it 'drops the response when the epoch changes during the Socialwise HTTP call' do
      allow(HTTParty).to receive(:post) do
        conversation.update!(additional_attributes: { 'socialwise_ownership_epoch' => 1 })
        http_response
      end
      expect(service).not_to receive(:create_conversation)

      service.perform
    end

    it 'revalidates immediately before starting the Socialwise HTTP call' do
      allow(service).to receive(:build_request_payload) do
        create_eligible_trigger
        {}
      end
      expect(HTTParty).not_to receive(:post)

      service.perform
    end
  end

  describe '#bot_should_respond?' do
    it 'allows open conversations with an old human reply when no explicit handoff exists' do
      allow(service).to receive(:has_agent_reply?).and_return(true)
      allow(service).to receive(:handoff_completed?).and_return(false)

      expect(service.send(:bot_should_respond?)).to be(true)
    end

    it 'blocks open conversations after explicit Socialwise handoff' do
      allow(service).to receive(:has_agent_reply?).and_return(false)
      allow(service).to receive(:handoff_completed?).and_return(true)

      expect(service.send(:bot_should_respond?)).to be(false)
    end

    it 'sees handoff flags written after the conversation was memoized' do
      service.send(:conversation)
      Conversation.find(conversation.id).update!(
        additional_attributes: {
          'socialwise_handoff_at' => Time.current.iso8601,
          'socialwise_handoff_by' => 'bot'
        }
      )

      expect(service.send(:handoff_completed?)).to be(true)
    end
  end

  describe '#process_response' do
    it 'does not send a late bot response after handoff was completed by another job' do
      service.send(:conversation)
      Conversation.find(conversation.id).update!(
        additional_attributes: {
          'socialwise_handoff_at' => Time.current.iso8601,
          'socialwise_handoff_by' => 'bot'
        }
      )

      expect(service).not_to receive(:create_conversation)

      service.send(:process_response, message, { 'text' => 'late bot reply' })
    end

    context 'with Instagram quick replies without message_format' do
      let(:instagram_channel) { create(:channel_instagram, account: account) }
      let(:instagram_inbox) { instagram_channel.inbox }
      let(:instagram_hook) do
        create(
          :integrations_hook,
          inbox: instagram_inbox,
          account: account,
          app_id: 'socialwise_flow',
          settings: { 'language' => 'pt-BR' }
        )
      end
      let(:instagram_conversation) { create(:conversation, account: account, inbox: instagram_inbox, status: :open) }
      let(:instagram_message) do
        create(:message, account: account, inbox: instagram_inbox, conversation: instagram_conversation)
      end
      let(:instagram_service) do
        described_class.new(event_name: 'message.created', hook: instagram_hook, event_data: { message: instagram_message })
      end

      it 'infers QUICK_REPLIES and sends the rich payload to the Instagram processor' do
        expect(Integrations::Socialwise::InstagramResponseProcessor).to receive(:process).with(
          {
            'message_format' => 'QUICK_REPLIES',
            'payload' => instagram_payload_without_format
          },
          instagram_message,
          ownership_check: kind_of(Proc)
        ).and_return(true)

        expect(instagram_service).not_to receive(:create_fallback_instagram_message)

        instagram_service.send(:process_response, instagram_message, { 'instagram' => instagram_payload_without_format })
      end

      it 'trusts the payload structure over a misleading message_format' do
        expect(Integrations::Socialwise::InstagramResponseProcessor).to receive(:process).with(
          {
            'message_format' => 'BUTTON_TEMPLATE',
            'payload' => {
              'template_type' => 'button',
              'text' => 'Escolha uma opção:',
              'buttons' => [
                { 'type' => 'postback', 'title' => 'Falar com atendente', 'payload' => '@falar_atendente' }
              ]
            }
          },
          instagram_message,
          ownership_check: kind_of(Proc)
        ).and_return(true)

        expect(instagram_service).not_to receive(:create_fallback_instagram_message)

        instagram_service.send(:process_response, instagram_message, { 'instagram' => button_payload_with_wrong_format })
      end
    end

    it 'passes the ownership predicate to the WhatsApp rich response delegate' do
      payload = { 'type' => 'text', 'text' => 'hello' }
      expect(Integrations::SocialwiseFlow::WhatsappResponseProcessor).to receive(:process).with(
        payload,
        message,
        ownership_check: kind_of(Proc)
      ).and_return(true)

      service.send(:process_whatsapp_response, message, payload)
    end

    it 'does not publish a fallback after ownership is lost during response processing' do
      calls = 0
      allow(service).to receive(:create_conversation) do
        calls += 1
        conversation.update!(additional_attributes: { 'socialwise_ownership_epoch' => 1 }) if calls == 1
        raise 'rendering failed'
      end

      service.send(:process_response, message, { 'text' => 'response' })

      expect(calls).to eq(1)
    end

    %w[handoff resolve].each do |action|
      it "publishes text before applying the #{action} action from the same authorized response" do
        expect(service).to receive(:create_conversation).with(message, { content: 'authorized response' }).ordered
        expect(service).to receive(:process_action).with(message, action, epoch: 0).ordered

        service.send(:process_response, message, { 'text' => 'authorized response', 'action' => action })
      end
    end

    it 'passes the immutable response epoch to a button action' do
      expect(service).to receive(:process_action).with(message, 'handoff', epoch: 0)

      service.send(:process_button_reaction, message, { 'action' => 'handoff' }, epoch: 0)
    end

    it 'passes the immutable response epoch to the button rescue action' do
      ownership_checks = 0
      allow(service).to receive(:publish_allowed?).and_wrap_original do |original, *arguments|
        ownership_checks += 1
        raise 'button processing failed' if ownership_checks == 2

        original.call(*arguments)
      end
      expect(service).to receive(:process_action).with(message, 'handoff', epoch: 0)

      service.send(:process_button_reaction, message, { 'action' => 'handoff' }, epoch: 0)
    end

    it 'revalidates before applying an action after a text effect' do
      allow(service).to receive(:create_conversation) do
        conversation.update!(additional_attributes: { 'socialwise_ownership_epoch' => 1 })
      end
      expect(service).not_to receive(:process_action)

      service.send(:process_response, message, { 'text' => 'first effect', 'action' => 'handoff' })
    end

    it 'revalidates between button reaction effect families' do
      allow(service).to receive(:send_emoji_reaction) do
        conversation.update!(additional_attributes: { 'socialwise_ownership_epoch' => 1 })
      end
      expect(service).not_to receive(:send_reaction_text)
      expect(service).not_to receive(:process_action)
      expect(service).not_to receive(:process_whatsapp_response)

      service.send(
        :process_button_reaction,
        message,
        {
          'emoji' => '✅',
          'text' => 'reaction text',
          'action' => 'handoff',
          'mapped' => { 'whatsapp' => { 'type' => 'text', 'text' => 'rich effect' } }
        }
      )
    end
  end

  describe 'Facebook rich payload mapping' do
    it 'revalidates after constructing the provider service and before performing it' do
      provider = instance_double(Facebook::SendOnFacebookService)
      allow(Facebook::SendOnFacebookService).to receive(:new) do
        conversation.update!(additional_attributes: { 'socialwise_ownership_epoch' => 1 })
        provider
      end
      expect(provider).not_to receive(:perform)

      service.send(:process_facebook_response, message, { 'text' => 'authorized text' })
    end

    it 'maps direct payloads by structure when message_format is misleading' do
      expect(service.send(:build_facebook_mapping_payload_for_cards, button_payload_with_wrong_format)).to eq(
        {
          'template_type' => 'button',
          'text' => 'Escolha uma opção:',
          'buttons' => [
            { 'type' => 'postback', 'title' => 'Falar com atendente', 'payload' => '@falar_atendente' }
          ]
        }
      )
    end

    it 'builds the Messenger send payload by structure when message_format is misleading' do
      expect(service.send(:build_facebook_send_message_payload, button_payload_with_wrong_format)).to eq(
        {
          'attachment' => {
            'type' => 'template',
            'payload' => {
              'template_type' => 'button',
              'text' => 'Escolha uma opção:',
              'buttons' => [
                { 'type' => 'postback', 'title' => 'Falar com atendente', 'payload' => '@falar_atendente' }
              ]
            }
          }
        }
      )
    end
  end

  describe '#create_fallback_instagram_message' do
    it 'uses the payload text instead of sending the internal placeholder' do
      expect(service).to receive(:create_conversation).with(
        message,
        { content: 'Olá! Sou a Ana e posso ajudar. Escolha uma opção:' }
      )

      service.send(:create_fallback_instagram_message, message, instagram_payload_without_format)
    end
  end

  describe '#send_typing_indicator_to_user' do
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
    let(:whatsapp_conversation) { create(:conversation, account: account, inbox: whatsapp_inbox, status: :open) }
    let(:whatsapp_message) do
      create(
        :message,
        account: account,
        inbox: whatsapp_inbox,
        conversation: whatsapp_conversation,
        source_id: 'wamid.inbound'
      )
    end
    let(:whatsapp_hook) do
      create(
        :integrations_hook,
        inbox: whatsapp_inbox,
        account: account,
        app_id: 'socialwise_flow',
        settings: { 'language' => 'pt-BR' }
      )
    end
    let(:whatsapp_service) do
      described_class.new(event_name: 'message.created', hook: whatsapp_hook, event_data: { message: whatsapp_message })
    end

    it 'revalidates ownership after provider construction and immediately before typing' do
      target_service = whatsapp_service
      target_message = whatsapp_message
      provider = instance_double(Whatsapp::Providers::WhatsappCloudService)
      allow(Whatsapp::Providers::WhatsappCloudService).to receive(:new) do
        whatsapp_conversation.update!(additional_attributes: { 'socialwise_ownership_epoch' => 1 })
        provider
      end
      expect(provider).not_to receive(:mark_read_with_typing)

      target_service.send(:send_typing_indicator_to_user, target_message)
    end
  end

  describe '#process_action ownership mutation' do
    %w[handoff resolve].each do |action|
      it "preserves a Captain fence that wins before the #{action} action lock" do
        conversation.update!(additional_attributes: { 'keep_me' => 'fresh', 'socialwise_ownership_epoch' => 0 })
        epoch = service.send(:execution_epoch)
        pause_guard = Integrations::SocialwiseFlow::OwnershipGuard.new(Conversation.find(conversation.id))
        pause_installed = false
        action_log = "[SOCIALWISE-FLOW] Executing #{action} action"
        allow(Rails.configuration.dispatcher).to receive(:dispatch)

        allow(Rails.logger).to receive(:info).and_wrap_original do |original, text, *arguments|
          if !pause_installed && text == action_log
            pause_installed = true
            pause_guard.pause_for_phase2!
          end

          original.call(text, *arguments)
        end

        service.send(:process_action, message, action, epoch: epoch)

        expect(pause_installed).to be(true)
        expect(conversation.reload).to be_open
        expect(conversation.waiting_since).to be_nil
        expect(conversation.additional_attributes).to include(
          'keep_me' => 'fresh',
          'socialwise_handoff_by' => 'captain_payment_phase2',
          'socialwise_ownership_epoch' => 1
        )
        if action == 'handoff'
          expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
            .with(Events::Types::CONVERSATION_BOT_HANDOFF, anything, anything)
        end
      end
    end

    it 'commits an authorized handoff before dispatching its bookkeeping event' do
      epoch = service.send(:execution_epoch)
      transaction_baseline = Conversation.connection.open_transactions
      dispatch_open_transactions = nil
      allow(Rails.configuration.dispatcher).to receive(:dispatch)
      expect(Rails.configuration.dispatcher).to receive(:dispatch)
        .with(
          Events::Types::CONVERSATION_BOT_HANDOFF,
          anything,
          hash_including(conversation: have_attributes(id: conversation.id))
        ).once do
          dispatch_open_transactions = Conversation.connection.open_transactions
          raise 'dispatch unavailable'
        end

      expect { service.send(:process_action, message, 'handoff', epoch: epoch) }
        .to raise_error(RuntimeError, 'dispatch unavailable')

      expect(dispatch_open_transactions).to eq(transaction_baseline)
      expect(conversation.reload).to be_open
      expect(conversation.waiting_since).to be_present
      expect(conversation.additional_attributes['socialwise_handoff_by']).to eq('bot')
    end
  end

  describe '#send_whatsapp_reaction_text ownership bookkeeping' do
    let(:reaction_response) do
      {
        'buttonId' => 'confirm-payment',
        'whatsapp' => { 'message_id' => 'wamid.inbound' }
      }
    end

    it 'records the provider message id even when ownership changes after the provider accepted it' do
      service.send(:execution_epoch)
      api_response = instance_double(
        HTTParty::Response,
        parsed_response: { 'messages' => [{ 'id' => 'wamid.provider-response' }] }
      )
      expect(service).to receive(:send_whatsapp_contextual_message_to_api)
        .with(conversation, 'wamid.inbound', 'Pagamento confirmado') do
          Integrations::SocialwiseFlow::OwnershipGuard.new(conversation).pause_for_phase2!
          api_response
        end

      expect do
        service.send(:send_whatsapp_reaction_text, conversation, 'Pagamento confirmado', reaction_response)
      end.to change { conversation.messages.where(source_id: 'wamid.provider-response').count }.by(1)

      provider_message = conversation.messages.find_by!(source_id: 'wamid.provider-response')
      expect(provider_message).to be_outgoing
      expect(provider_message.additional_attributes['skip_send_reply']).to be(true)
    end

    it 'keeps the ownership fence before local creation when the provider returns no message id' do
      service.send(:execution_epoch)
      api_response = instance_double(HTTParty::Response, parsed_response: { 'messages' => [] })
      expect(service).to receive(:send_whatsapp_contextual_message_to_api)
        .with(conversation, 'wamid.inbound', 'Pagamento confirmado') do
          conversation.update!(additional_attributes: { 'socialwise_ownership_epoch' => 1 })
          api_response
        end

      expect do
        service.send(:send_whatsapp_reaction_text, conversation, 'Pagamento confirmado', reaction_response)
      end.not_to(change { conversation.messages.outgoing.count })
    end
  end

  describe '#mark_handoff_completed' do
    it 'locks and merges from fresh state while replacing only Captain handoff ownership' do
      stale_argument = Conversation.find(conversation.id)
      locked_snapshot = Conversation.find(conversation.id)
      captain_handoff_at = 1.minute.ago.iso8601(6)
      Conversation.find(conversation.id).update!(
        additional_attributes: {
          'keep_me' => 'fresh',
          'socialwise_ownership_epoch' => 4,
          'socialwise_handoff_at' => captain_handoff_at,
          'socialwise_handoff_by' => 'captain_payment_phase2'
        }
      )
      allow(Conversation).to receive(:find).with(conversation.id).and_return(locked_snapshot)
      expect(locked_snapshot).to receive(:with_lock).and_call_original

      service.send(:mark_handoff_completed, stale_argument, by: 'agent_reply')

      expect(conversation.reload.additional_attributes).to include(
        'keep_me' => 'fresh',
        'socialwise_ownership_epoch' => 4,
        'socialwise_handoff_by' => 'agent_reply'
      )
      expect(conversation.additional_attributes['socialwise_handoff_at']).not_to eq(captain_handoff_at)
    end
  end

  describe '#should_run_processor?' do
    it 'preserves subsecond precision so a delayed resolve does not clear a newer human handoff' do
      resolve_cutoff = Time.zone.parse('2026-07-16 12:00:00.100000')
      handoff_time = resolve_cutoff + 0.2.seconds

      travel_to(handoff_time, with_usec: true) do
        service.send(:mark_handoff_completed, conversation, by: 'agent_reply')
      end
      Integrations::SocialwiseFlow::OwnershipGuard.new(conversation).release_for_resolve!(cutoff: resolve_cutoff)

      expect(conversation.reload.additional_attributes).to include(
        'socialwise_handoff_at' => handoff_time.iso8601(6),
        'socialwise_handoff_by' => 'agent_reply'
      )
    end

    it 'marks handoff when a human agent sends an outgoing reply' do
      agent_reply = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        sender: create(:user, account: account)
      )

      expect(service.send(:should_run_processor?, agent_reply)).to be_nil
      expect(conversation.reload.additional_attributes['socialwise_handoff_at']).to be_present
      expect(conversation.additional_attributes['socialwise_handoff_by']).to eq('agent_reply')
    end

    it 'does not mark handoff again for outgoing message updates' do
      updated_service = described_class.new(event_name: 'message.updated', hook: hook, event_data: { message: message })
      agent_reply = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        sender: create(:user, account: account)
      )

      expect(updated_service.send(:should_run_processor?, agent_reply)).to be_nil
      expect(conversation.reload.additional_attributes['socialwise_handoff_at']).to be_nil
    end

    it 'marks handoff and opens pending conversation when Instagram native app echo is received' do
      conversation.update!(status: :pending)
      native_echo = build(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        sender: nil,
        content_attributes: { external_echo: true }
      )
      native_echo.save!

      expect(service).to receive(:discard_pending_debounce_buffer).with(conversation.id, force: true)

      expect(service.send(:should_run_processor?, native_echo)).to be_nil
      expect(conversation.reload.additional_attributes['socialwise_handoff_at']).to be_present
      expect(conversation.additional_attributes['socialwise_handoff_by']).to eq('external_echo')
      expect(conversation.status).to eq('open')
    end

    it 'allows pending conversations with old handoff so resolved conversations can restart the bot' do
      conversation.update!(
        status: :pending,
        additional_attributes: {
          'socialwise_handoff_at' => Time.current.iso8601,
          'socialwise_handoff_by' => 'agent_reply'
        }
      )

      expect(service.send(:bot_should_respond?)).to be(true)
    end
  end
end
