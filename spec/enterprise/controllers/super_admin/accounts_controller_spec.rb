require 'rails_helper'

RSpec.describe 'Enterprise Super Admin accounts API', type: :request do
  let!(:super_admin) { create(:super_admin) }
  let!(:account) { create(:account) }

  describe 'GET /super_admin/accounts/{account_id}' do
    it 'renders the Captain Payment Phase 2 toggle with the current state' do
      sign_in(super_admin, scope: :super_admin)

      get "/super_admin/accounts/#{account.id}"

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Captain Payment Phase 2 is currently <strong>Disabled</strong>')
    end
  end

  describe 'POST /super_admin/accounts/{account_id}/toggle_captain_payment_phase2' do
    context 'when it is an unauthenticated user' do
      it 'redirects without touching the account' do
        post "/super_admin/accounts/#{account.id}/toggle_captain_payment_phase2"
        expect(response).to have_http_status(:redirect)
        expect(account.reload.internal_attributes['captain_payment_phase2']).to be_nil
      end
    end

    context 'when it is an authenticated super admin' do
      before do
        sign_in(super_admin, scope: :super_admin)
      end

      it 'enables the flag when it is absent' do
        post "/super_admin/accounts/#{account.id}/toggle_captain_payment_phase2"

        expect(response).to have_http_status(:redirect)
        expect(flash[:notice]).to eq('Captain Payment Phase 2 enabled')
        expect(account.reload.internal_attributes['captain_payment_phase2']).to be(true)
      end

      it 'disables the flag when it is enabled' do
        account.update!(internal_attributes: account.internal_attributes.merge('captain_payment_phase2' => true))

        post "/super_admin/accounts/#{account.id}/toggle_captain_payment_phase2"

        expect(response).to have_http_status(:redirect)
        expect(flash[:notice]).to eq('Captain Payment Phase 2 disabled')
        expect(account.reload.internal_attributes['captain_payment_phase2']).to be(false)
      end

      it 'preserves other internal attributes when toggling' do
        account.update!(internal_attributes: account.internal_attributes.merge('manually_managed_features' => ['sla']))

        post "/super_admin/accounts/#{account.id}/toggle_captain_payment_phase2"

        expect(account.reload.internal_attributes['manually_managed_features']).to eq(['sla'])
        expect(account.internal_attributes['captain_payment_phase2']).to be(true)
      end
    end
  end
end
