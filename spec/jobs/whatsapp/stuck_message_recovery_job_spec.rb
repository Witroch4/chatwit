require 'rails_helper'

RSpec.describe Whatsapp::StuckMessageRecoveryJob do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, source_id: '5517999999999') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox) }

  def stuck_message(created_at: 30.minutes.ago, additional_attributes: {})
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      status: :sent,
      source_id: 'wamid.original',
      created_at: created_at,
      additional_attributes: additional_attributes
    )
  end

  describe '#perform' do
    it 'resends a message stuck in sent once, points it at the new wamid and records the attempt', :aggregate_failures do
      message = stuck_message
      allow_any_instance_of(Channel::Whatsapp).to receive(:send_message).and_return('wamid.resent') # rubocop:disable RSpec/AnyInstance

      described_class.perform_now

      message.reload
      expect(message.status).to eq('sent')
      expect(message.source_id).to eq('wamid.resent')
      expect(message.additional_attributes['stuck_recovery_resent_at']).to be_present
    end

    it 'does not flag the message while the resend is still inside its grace period', :aggregate_failures do
      message = stuck_message(additional_attributes: { 'stuck_recovery_resent_at' => 3.minutes.ago.iso8601 })

      described_class.perform_now

      expect(message.reload.status).to eq('sent')
    end

    it 'flags the message as failed after the resend stays unconfirmed, without blaming a single cause', :aggregate_failures do
      message = stuck_message(additional_attributes: { 'stuck_recovery_resent_at' => 15.minutes.ago.iso8601 })

      described_class.perform_now

      message.reload
      expect(message.status).to eq('failed')
      expect(message.external_error).to eq(described_class::UNDELIVERED_ERROR)
      # aceita pela Meta, sem confirmação; lista as três causas possíveis; manda confirmar antes de reenviar
      expect(message.external_error).to include('Aceita pelo WhatsApp', 'sem confirmação de entrega', 'celular do contato', 'a Meta ou o sistema')
      expect(message.external_error).to include('por outro meio antes de reenviar')
      expect(message.external_error).not_to match(/falha|erro/i)
    end

    it 'leaves a message alone when delivery was confirmed in the meantime' do
      message = stuck_message(additional_attributes: { 'stuck_recovery_resent_at' => 15.minutes.ago.iso8601 })
      message.update!(status: :delivered)

      described_class.perform_now

      expect(message.reload.status).to eq('delivered')
    end

    it 'never resends or flags an official template message', :aggregate_failures do
      message = stuck_message(additional_attributes: { 'stuck_recovery_resent_at' => 15.minutes.ago.iso8601 })
      message.update!(content_attributes: { 'template_payload' => { 'name' => 'hello' } })

      described_class.perform_now

      expect(message.reload.status).to eq('sent')
    end
  end
end
