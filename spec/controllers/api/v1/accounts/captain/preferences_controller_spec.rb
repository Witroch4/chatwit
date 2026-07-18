# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::Preferences', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  describe 'GET /api/v1/accounts/{account.id}/captain/preferences' do
    context 'when the WitDev route is enabled' do
      before do
        allow(Chatwit::LlmProxy).to receive(:route_witdev?).and_return(true)
        allow(Chatwit::LlmProxy).to receive(:model).and_return('witdev_claude/sonnet')
        allow(Chatwit::LlmProxy).to receive(:catalog_source).and_return('litellm_proxy')
        allow(Chatwit::LlmProxy).to receive(:operational_catalog?).and_return(true)
        allow(Chatwit::LlmProxy).to receive(:operational_models).and_return(
          [
            { 'value' => 'witdev/gpt-5.5', 'label' => 'GPT-5.5', 'provider' => 'witdev',
              'provider_label' => 'WitDev Codex', 'active' => true, 'hidden' => false }
          ]
        )
      end

      it 'returns central catalog metadata and generative feature options' do
        get "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(json_response.dig(:catalog, :route)).to eq('witdev')
        expect(json_response.dig(:catalog, :source)).to eq('litellm_proxy')
        expect(json_response.dig(:features, :editor, :models, 0, :id)).to eq('witdev/gpt-5.5')
      end
    end

    context 'when the Chatwoot route is enabled' do
      it 'omits WitDev catalog metadata from the legacy payload' do
        allow(Chatwit::LlmProxy).to receive(:route_witdev?).and_return(false)

        get "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(json_response).not_to have_key(:catalog)
      end
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/captain/preferences",
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent' do
      it 'returns captain config' do
        get "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(json_response).to have_key(:providers)
        expect(json_response).to have_key(:models)
        expect(json_response).to have_key(:features)
      end
    end

    context 'when it is an admin' do
      it 'returns captain config' do
        get "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(json_response).to have_key(:providers)
        expect(json_response).to have_key(:models)
        expect(json_response).to have_key(:features)
      end
    end
  end

  describe 'PUT /api/v1/accounts/{account.id}/captain/preferences' do
    context 'when the WitDev route is enabled' do
      before do
        allow(Chatwit::LlmProxy).to receive(:route_witdev?).and_return(true)
        allow(Chatwit::LlmProxy).to receive(:model).and_return('witdev_claude/sonnet')
        allow(Chatwit::LlmProxy).to receive(:catalog_source).and_return('litellm_proxy')
        allow(Chatwit::LlmProxy).to receive(:operational_catalog?).and_return(true)
        allow(Chatwit::LlmProxy).to receive(:operational_models).and_return(
          [
            { 'value' => 'witdev/gpt-5.5', 'label' => 'GPT-5.5', 'provider' => 'witdev',
              'provider_label' => 'WitDev Codex', 'active' => true, 'hidden' => false }
          ]
        )
      end

      it 'persists an exact canonical alias accepted by the proxy catalog' do
        allow(Chatwit::LlmProxy).to receive(:resolve_model!).with('witdev/gpt-5.5').and_return('witdev/gpt-5.5')

        put "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: admin.create_new_auth_token,
            params: { captain_models: { editor: 'witdev/gpt-5.5' } },
            as: :json

        expect(response).to have_http_status(:success)
        expect(account.reload.captain_models['editor']).to eq('witdev/gpt-5.5')
      end

      it 'rejects an unavailable canonical alias without changing saved models' do
        allow(Chatwit::LlmProxy).to receive(:resolve_model!)
          .with('witdev/gpt-5.5')
          .and_raise(Chatwit::LlmProxy::ModelUnavailableError, 'LLM model alias is unavailable: witdev/gpt-5.5')
        original_models = account.captain_models

        put "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: admin.create_new_auth_token,
            params: { captain_models: { editor: 'witdev/gpt-5.5' } },
            as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(account.reload.captain_models).to eq(original_models)
      end

      it 'rejects an unavailable catalog without changing saved models' do
        allow(Chatwit::LlmProxy).to receive(:resolve_model!)
          .with('witdev/gpt-5.5')
          .and_raise(Chatwit::LlmProxy::CatalogUnavailableError, 'The canonical LLM catalog is unavailable')
        original_models = account.captain_models

        put "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: admin.create_new_auth_token,
            params: { captain_models: { editor: 'witdev/gpt-5.5' } },
            as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(account.reload.captain_models).to eq(original_models)
      end
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        put "/api/v1/accounts/#{account.id}/captain/preferences",
            params: { captain_models: { editor: 'gpt-4.1-mini' } },
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent' do
      it 'returns forbidden' do
        put "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: agent.create_new_auth_token,
            params: { captain_models: { editor: 'gpt-4.1-mini' } },
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an admin' do
      it 'updates captain_models' do
        put "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: admin.create_new_auth_token,
            params: { captain_models: { editor: 'gpt-4.1-mini' } },
            as: :json

        expect(response).to have_http_status(:success)
        expect(json_response).to have_key(:providers)
        expect(json_response).to have_key(:models)
        expect(json_response).to have_key(:features)
        expect(account.reload.captain_models['editor']).to eq('gpt-4.1-mini')
      end

      it 'updates captain_features' do
        put "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: admin.create_new_auth_token,
            params: { captain_features: { editor: true } },
            as: :json

        expect(response).to have_http_status(:success)
        expect(json_response).to have_key(:providers)
        expect(json_response).to have_key(:models)
        expect(json_response).to have_key(:features)
        expect(account.reload.captain_features['editor']).to be true
      end

      it 'merges with existing captain_models' do
        account.update!(captain_models: { 'editor' => 'gpt-4.1-mini', 'assistant' => 'gpt-5.1' })

        put "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: admin.create_new_auth_token,
            params: { captain_models: { editor: 'gpt-4.1' } },
            as: :json

        expect(response).to have_http_status(:success)
        expect(json_response).to have_key(:providers)
        expect(json_response).to have_key(:models)
        expect(json_response).to have_key(:features)
        models = account.reload.captain_models
        expect(models['editor']).to eq('gpt-4.1')
        expect(models['assistant']).to eq('gpt-5.1') # Preserved
      end

      it 'merges with existing captain_features' do
        account.update!(captain_features: { 'editor' => true, 'assistant' => false })

        put "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: admin.create_new_auth_token,
            params: { captain_features: { editor: false } },
            as: :json

        expect(response).to have_http_status(:success)
        expect(json_response).to have_key(:providers)
        expect(json_response).to have_key(:models)
        expect(json_response).to have_key(:features)
        features = account.reload.captain_features
        expect(features['editor']).to be false
        expect(features['assistant']).to be false # Preserved
      end

      it 'updates both models and features in single request' do
        put "/api/v1/accounts/#{account.id}/captain/preferences",
            headers: admin.create_new_auth_token,
            params: {
              captain_models: { editor: 'gpt-4.1-mini' },
              captain_features: { editor: true }
            },
            as: :json

        expect(response).to have_http_status(:success)
        expect(json_response).to have_key(:providers)
        expect(json_response).to have_key(:models)
        expect(json_response).to have_key(:features)
        account.reload
        expect(account.captain_models['editor']).to eq('gpt-4.1-mini')
        expect(account.captain_features['editor']).to be true
      end
    end
  end
end
