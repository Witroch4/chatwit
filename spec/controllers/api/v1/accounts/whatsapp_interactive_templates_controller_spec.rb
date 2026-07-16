require 'rails_helper'

RSpec.describe 'WhatsApp Interactive Templates API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:template) do
    account.whatsapp_interactive_templates.create!(
      name: 'payment_cta',
      template_type: 'cta_url',
      header_type: 'image',
      header_image_url: 'https://example.com/old-header.png',
      body_text: 'Old body',
      footer_text: 'Old footer',
      button_text: 'Pay now',
      payload: { 'type' => 'cta_url', 'body' => { 'text' => 'Old body' } }
    )
  end

  describe 'PATCH /api/v1/accounts/:account_id/whatsapp_interactive_templates/:id' do
    it 'updates every editable field and rebuilds the WhatsApp payload' do
      patch "/api/v1/accounts/#{account.id}/whatsapp_interactive_templates/#{template.id}",
            headers: administrator.create_new_auth_token,
            params: {
              whatsapp_interactive_template: {
                name: 'updated_payment_cta',
                template_type: 'cta_url',
                header_type: 'image',
                header_image_url: 'https://example.com/new-header.png',
                body_text: 'Updated body',
                footer_text: 'Updated footer',
                button_text: 'Open checkout',
                static_url: 'https://checkout.example.com/pay',
                quick_replies: [{ text: 'Need help' }]
              }
            },
            as: :json

      expect(response).to have_http_status(:ok)

      template.reload
      expect(template.name).to eq('updated_payment_cta')
      expect(template.header_image_url).to eq('https://example.com/new-header.png')
      expect(template.body_text).to eq('Updated body')
      expect(template.payload.dig('body', 'text')).to eq('Updated body')
    end

    it 'rebuilds the payload from persisted attributes on a partial update' do
      patch "/api/v1/accounts/#{account.id}/whatsapp_interactive_templates/#{template.id}",
            headers: administrator.create_new_auth_token,
            params: { whatsapp_interactive_template: { name: 'renamed_cta' } },
            as: :json

      expect(response).to have_http_status(:ok)

      template.reload
      expect(template.name).to eq('renamed_cta')
      expect(template.body_text).to eq('Old body')
      expect(template.payload.dig('body', 'text')).to eq('Old body')
    end
  end

  describe 'quick reply id preservation' do
    let(:quick_reply_template) do
      account.whatsapp_interactive_templates.create!(
        name: 'quick_replies_flow',
        template_type: 'quick_replies',
        header_type: 'none',
        body_text: 'Pick an option',
        button_text: '',
        payload: {
          'type' => 'button',
          'body' => { 'text' => 'Pick an option' },
          'action' => {
            'buttons' => [
              { 'type' => 'reply', 'reply' => { 'id' => 'qr_1', 'title' => 'Yes' } },
              { 'type' => 'reply', 'reply' => { 'id' => 'qr_2', 'title' => 'Talk to agent' } }
            ]
          }
        }
      )
    end

    it 'keeps existing button ids stable when a reply is removed' do
      patch "/api/v1/accounts/#{account.id}/whatsapp_interactive_templates/#{quick_reply_template.id}",
            headers: administrator.create_new_auth_token,
            params: {
              whatsapp_interactive_template: {
                name: 'quick_replies_flow',
                template_type: 'quick_replies',
                header_type: 'none',
                body_text: 'Pick an option',
                quick_replies: [{ id: 'qr_2', text: 'Talk to agent' }]
              }
            },
            as: :json

      expect(response).to have_http_status(:ok)

      quick_reply_template.reload
      button_ids = quick_reply_template.payload.dig('action', 'buttons').map { |b| b.dig('reply', 'id') }
      expect(button_ids).to eq(['qr_2'])
    end
  end
end
