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
  end
end
