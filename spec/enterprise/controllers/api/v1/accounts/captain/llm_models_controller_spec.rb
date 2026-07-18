require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::LlmModels', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  describe 'GET /api/v1/accounts/:account_id/captain/llm_models' do
    context 'when the central catalog responds' do
      before do
        allow(Chatwit::LlmProxy).to receive(:operational_models).and_return(
          [{ 'value' => 'witdev_claude/sonnet', 'label' => 'Claude Sonnet', 'provider_label' => 'Anthropic' }]
        )
        allow(Chatwit::LlmProxy).to receive(:catalog_source).and_return('litellm_proxy')
        allow(Chatwit::LlmProxy).to receive(:operational_catalog?).and_return(true)
      end

      it 'returns the operational catalog and its exact status for admins' do
        get "/api/v1/accounts/#{account.id}/captain/llm_models", headers: admin.create_new_auth_token

        expect(response).to have_http_status(:ok)
        expect(json_response).to include(source: 'litellm_proxy', operational: true)
        expect(json_response.dig(:models, 0, :value)).to eq('witdev_claude/sonnet')
        expect(json_response[:models].first[:label]).to eq('Claude Sonnet')
        expect(json_response[:models].first[:provider_label]).to eq('Anthropic')
      end
    end

    context 'when the central catalog is unavailable' do
      before do
        allow(Chatwit::LlmProxy).to receive(:operational_models).and_return([])
        allow(Chatwit::LlmProxy).to receive(:catalog_source).and_return('unavailable')
        allow(Chatwit::LlmProxy).to receive(:operational_catalog?).and_return(false)
      end

      it 'degrades to an empty list with a stable 200' do
        get "/api/v1/accounts/#{account.id}/captain/llm_models", headers: admin.create_new_auth_token

        expect(response).to have_http_status(:ok)
        expect(json_response[:models]).to eq([])
        expect(json_response[:source]).to eq('unavailable')
        expect(json_response[:operational]).to be(false)
      end
    end

    context 'when the user is an agent' do
      before { allow(Chatwit::LlmProxy).to receive(:operational_models).and_return([]) }

      it 'is unauthorized' do
        get "/api/v1/accounts/#{account.id}/captain/llm_models", headers: agent.create_new_auth_token

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when unauthenticated' do
      it 'is unauthorized' do
        get "/api/v1/accounts/#{account.id}/captain/llm_models"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
