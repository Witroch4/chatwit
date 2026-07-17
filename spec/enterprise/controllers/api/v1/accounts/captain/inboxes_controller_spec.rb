require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::Inboxes', type: :request do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:inbox2) { create(:inbox, account: account) }
  let!(:captain_inbox) { create(:captain_inbox, captain_assistant: assistant, inbox: inbox) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  describe 'GET /api/v1/accounts/:account_id/captain/assistants/:assistant_id/inboxes' do
    context 'when user is authorized' do
      it 'returns a list of inboxes for the assistant' do
        get "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/inboxes",
            headers: agent.create_new_auth_token

        expect(response).to have_http_status(:ok)
        expect(json_response[:payload].first[:id]).to eq(captain_inbox.inbox.id)
        expect(json_response[:payload].first[:captain_mode]).to eq('continuous')
      end

      it 'exposes phase2 settings and the default prompt' do
        captain_inbox.update!(mode: :phase2_only, phase2_model: 'witdev_claude/sonnet')

        get "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/inboxes",
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:ok)
        expect(json_response[:payload].first[:phase2_model]).to eq('witdev_claude/sonnet')
        expect(json_response[:payload].first[:default_prompt]).to eq(Captain::PaymentReview::DEFAULT_PROMPT)
      end
    end

    context 'when user is unauthorized' do
      it 'returns unauthorized status' do
        get "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/inboxes"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when assistant does not exist' do
      it 'returns not found status' do
        get "/api/v1/accounts/#{account.id}/captain/assistants/999999/inboxes",
            headers: agent.create_new_auth_token

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/accounts/:account/captain/assistants/:assistant_id/inboxes' do
    let(:valid_params) do
      {
        inbox: {
          inbox_id: inbox2.id,
          mode: 'phase2_only'
        }
      }
    end

    context 'when user is authorized' do
      it 'creates a new captain inbox' do
        expect do
          post "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/inboxes",
               params: valid_params,
               headers: admin.create_new_auth_token
        end.to change(CaptainInbox, :count).by(1)

        expect(response).to have_http_status(:success)
        expect(json_response[:id]).to eq(inbox2.id)
        expect(json_response[:captain_mode]).to eq('phase2_only')
        expect(CaptainInbox.find_by!(inbox: inbox2)).to be_phase2_only
      end

      it 'keeps continuous as the default for existing clients that omit mode' do
        post "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/inboxes",
             params: { inbox: { inbox_id: inbox2.id } },
             headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        expect(CaptainInbox.find_by!(inbox: inbox2)).to be_continuous
        expect(json_response[:captain_mode]).to eq('continuous')
      end

      it 'persists and exposes phase2 model, prompt and payment presets' do
        preset = create(:payment_preset, account: account)

        post "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/inboxes",
             params: { inbox: { inbox_id: inbox2.id, mode: 'phase2_only', phase2_model: 'witdev_claude/sonnet',
                                phase2_prompt: 'Revise o pagamento', phase2_payment_preset_ids: [preset.id] } },
             headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        captain_inbox = CaptainInbox.find_by!(inbox: inbox2)
        expect(captain_inbox.phase2_model).to eq('witdev_claude/sonnet')
        expect(captain_inbox.phase2_prompt).to eq('Revise o pagamento')
        expect(captain_inbox.phase2_payment_preset_ids).to eq([preset.id])
        expect(json_response[:phase2_model]).to eq('witdev_claude/sonnet')
        expect(json_response[:phase2_payment_preset_ids]).to eq([preset.id])
        expect(json_response[:default_prompt]).to eq(Captain::PaymentReview::DEFAULT_PROMPT)
      end

      context 'when inbox does not exist' do
        it 'returns not found status' do
          post "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/inboxes",
               params: { inbox: { inbox_id: 999_999 } },
               headers: admin.create_new_auth_token

          expect(response).to have_http_status(:not_found)
        end
      end

      context 'when params are invalid' do
        it 'returns unprocessable entity status' do
          post "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/inboxes",
               params: {},
               headers: admin.create_new_auth_token

          expect(response).to have_http_status(:unprocessable_entity)
        end
      end
    end

    context 'when user is agent' do
      it 'returns unauthorized status' do
        post "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/inboxes",
             params: valid_params,
             headers: agent.create_new_auth_token

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/captain/assistants/:assistant_id/inboxes/:inbox_id' do
    context 'when user is authorized' do
      it 'deletes the captain inbox' do
        expect do
          delete "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/inboxes/#{inbox.id}",
                 headers: admin.create_new_auth_token
        end.to change(CaptainInbox, :count).by(-1)

        expect(response).to have_http_status(:no_content)
      end

      context 'when captain inbox does not exist' do
        it 'returns not found status' do
          delete "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/inboxes/999999",
                 headers: admin.create_new_auth_token

          expect(response).to have_http_status(:not_found)
        end
      end
    end
  end
end
