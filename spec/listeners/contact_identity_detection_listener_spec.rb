require 'rails_helper'

RSpec.describe ContactIdentityDetectionListener do
  subject(:listener) { described_class.instance }

  let(:account) { create(:account) }
  let(:contact) do
    create(:contact, account: account, email: nil, name: 'WITALO ROCHA DO NASCIMENTO', phone_number: '+5585997550136')
  end
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  # Real payload observed in production (message 72786): Meta generates the keys.
  let(:flow_answers) do
    {
      'screen_0_Name_0' => 'Witalo ',
      'flow_token' => '59F75FE9-D1AC-4905-AEB0-97733C2C0C20',
      'flow_id' => '1098697149365768',
      'screen_0_Email_1' => 'Witalo_rocha@hotmail.com'
    }
  end

  def build_message(content:, content_attributes: {}, message_type: :incoming)
    create(
      :message,
      account: account,
      conversation: conversation,
      message_type: message_type,
      content: content,
      content_attributes: content_attributes
    )
  end

  def flow_message(answers = flow_answers)
    build_message(
      content: 'Submitted a flow response',
      content_attributes: {
        'whatsapp_flow_response' => { 'name' => 'flow', 'body' => 'Sent', 'response_json' => answers }
      }
    )
  end

  def dispatch(message)
    listener.message_created(Events::Base.new(:message_created, Time.zone.now, message: message))
  end

  describe 'WhatsApp Flow response' do
    it 'saves the email answered in the form' do
      dispatch(flow_message)

      expect(contact.reload.email).to eq('witalo_rocha@hotmail.com')
    end

    it 'ignores flow metadata keys when looking for answers' do
      dispatch(flow_message({ 'flow_token' => 'name@token.com', 'flow_id' => '123' }))

      expect(contact.reload.email).to be_nil
    end

    it 'does not overwrite an email the contact already has' do
      contact.update!(email: 'antigo@witdev.com.br')

      dispatch(flow_message)

      expect(contact.reload.email).to eq('antigo@witdev.com.br')
    end

    it 'keeps a real contact name untouched' do
      dispatch(flow_message)

      expect(contact.reload.name).to eq('WITALO ROCHA DO NASCIMENTO')
    end

    it 'fills the name when the contact is still named after the phone number' do
      contact.update!(name: '+5585997550136')

      dispatch(flow_message)

      expect(contact.reload.name).to eq('Witalo')
    end

    it 'ignores answers that are not a valid email' do
      dispatch(flow_message({ 'screen_0_Email_1' => 'nao-e-email' }))

      expect(contact.reload.email).to be_nil
    end
  end

  describe 'free text' do
    it 'still detects an email typed in the message body' do
      dispatch(build_message(content: 'meu email eh witalo@witdev.com.br, obrigado'))

      expect(contact.reload.email).to eq('witalo@witdev.com.br')
    end

    it 'never infers a name from free text' do
      contact.update!(name: '+5585997550136')

      dispatch(build_message(content: 'aqui eh o Witalo falando'))

      expect(contact.reload.name).to eq('+5585997550136')
    end

    it 'ignores outgoing messages' do
      dispatch(build_message(content: 'contato@witdev.com.br', message_type: :outgoing))

      expect(contact.reload.email).to be_nil
    end
  end
end
