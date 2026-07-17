require 'rails_helper'

RSpec.describe Captain::PaymentReview::HistoryProjector do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:run) do
    create(:captain_payment_review_run, conversation: conversation, trigger_message_id: watermark_id)
  end
  let(:watermark_id) { nil }

  def project
    described_class.new(run).project
  end

  describe '#project' do
    context 'with the watermark boundary' do
      let!(:before_message) { create(:message, conversation: conversation, message_type: :incoming, content: 'antes') }
      let!(:after_message) { create(:message, conversation: conversation, message_type: :incoming, content: 'depois') }
      let(:watermark_id) { before_message.id }

      it 'projects only messages up to the run watermark' do
        contents = project.map { |entry| entry[:content] }
        expect(contents).to include('antes')
        expect(contents).not_to include('depois')
      end

      it 'prefers the decision watermark when advanced' do
        run.update!(decision_watermark_message_id: after_message.id)
        expect(project.map { |entry| entry[:content] }).to include('depois')
      end
    end

    it 'limits the projection to the last 30 public messages' do
      35.times { |index| create(:message, conversation: conversation, message_type: :incoming, content: "msg #{index}") }
      run.update!(trigger_message_id: conversation.messages.maximum(:id))
      projected = project
      expect(projected.size).to eq(30)
      expect(projected.last[:content]).to eq('msg 34')
      expect(projected.map { |entry| entry[:content] }).not_to include('msg 0')
    end

    it 'excludes private notes and activity messages' do
      create(:message, conversation: conversation, message_type: :outgoing, private: true, content: 'nota privada')
      create(:message, conversation: conversation, message_type: :activity, content: 'atividade')
      visible = create(:message, conversation: conversation, message_type: :incoming, content: 'ola')
      run.update!(trigger_message_id: conversation.messages.maximum(:id))

      contents = project.map { |entry| entry[:content] }
      expect(contents).to eq(['ola'])
      expect(visible.private).to be(false)
    end

    it 'replaces interactive payment payloads and checkout URLs with the CTA marker' do
      create(:message, conversation: conversation, message_type: :outgoing,
                       content: 'Pague', content_type: 'integrations',
                       content_attributes: { interactive: { type: 'cta_url' } })
      create(:message, conversation: conversation, message_type: :outgoing,
                       content: 'Segue: https://checkout.infinitepay.io/handle/slug-123')
      run.update!(trigger_message_id: conversation.messages.maximum(:id))

      contents = project.map { |entry| entry[:content] }
      expect(contents).to all(satisfy { |text| text.exclude?('checkout.infinitepay.io') && text.exclude?('slug-123') })
      expect(contents.join).to include(described_class::CTA_MARKER)
    end

    it 'replaces CNPJ/CPF values with the pix marker and receipt URLs with the receipt marker' do
      create(:message, conversation: conversation, message_type: :outgoing,
                       content: 'Pode pagar no CNPJ 57.944.155/0001-01 ou veja https://recibo.infinitepay.io/r/abc')
      run.update!(trigger_message_id: conversation.messages.maximum(:id))

      text = project.map { |entry| entry[:content] }.join
      expect(text).not_to include('57.944.155/0001-01')
      expect(text).not_to include('recibo.infinitepay.io')
      expect(text).to include(described_class::PIX_MARKER)
      expect(text).to include(described_class::RECEIPT_MARKER)
    end

    it 'never exposes raw content_attributes' do
      create(:message, conversation: conversation, message_type: :outgoing,
                       content: 'texto', content_attributes: { external_created_at: 1, secret_blob: 'x' })
      run.update!(trigger_message_id: conversation.messages.maximum(:id))

      entry = project.last
      expect(entry.keys).to contain_exactly(:role, :content)
    end

    it 'labels lead and agent roles' do
      create(:message, conversation: conversation, message_type: :incoming, content: 'oi')
      create(:message, conversation: conversation, message_type: :outgoing, content: 'ola')
      run.update!(trigger_message_id: conversation.messages.maximum(:id))

      expect(project.map { |entry| entry[:role] }).to eq(%w[lead agent])
    end
  end
end
