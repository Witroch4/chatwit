require 'rails_helper'

RSpec.describe 'Payment Presets API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:interactive_template) do
    account.whatsapp_interactive_templates.create!(
      name: 'payment_cta',
      template_type: 'cta_url',
      header_type: 'none',
      body_text: 'Use this payment link',
      button_text: 'Pay now',
      payload: { 'type' => 'cta_url' }
    )
  end

  describe 'POST /api/v1/accounts/:account_id/payment_presets' do
    it 'persists the selected interactive template' do
      post "/api/v1/accounts/#{account.id}/payment_presets",
           headers: administrator.create_new_auth_token,
           params: {
             payment_preset: {
               name: 'Payment CTA',
               amount_cents: 27_000,
               description: 'Single payment',
               whatsapp_interactive_template_id: interactive_template.id
             }
           },
           as: :json

      expect(response).to have_http_status(:created)
      expect(account.payment_presets.last.whatsapp_interactive_template).to eq(interactive_template)
    end
  end
end
