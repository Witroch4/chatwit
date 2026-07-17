require 'rails_helper'

RSpec.describe 'Conversation Label API', type: :request do
  let(:account) { create(:account) }

  describe 'GET /api/v1/accounts/{account.id}/conversations/<id>/labels' do
    let(:conversation) { create(:conversation, account: account) }

    before do
      conversation.update_labels('label1, label2')
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get api_v1_account_conversation_labels_url(account_id: account.id, conversation_id: conversation.display_id)
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user with access to the conversation' do
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, inbox: conversation.inbox, user: agent)
      end

      it 'returns all the labels for the conversation' do
        get api_v1_account_conversation_labels_url(account_id: account.id, conversation_id: conversation.display_id),
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.body).to include('label1')
        expect(response.body).to include('label2')
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/conversations/<id>/labels' do
    let(:conversation) { create(:conversation, account: account) }

    before do
      conversation.update_labels('label1, label2')
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post api_v1_account_conversation_labels_url(account_id: account.id, conversation_id: conversation.display_id),
             params: { labels: %w[label3 label4] },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user with access to the conversation' do
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        conversation.update_labels('label1, label2')
        create(:inbox_member, inbox: conversation.inbox, user: agent)
      end

      it 'creates labels for the conversation' do
        post api_v1_account_conversation_labels_url(account_id: account.id, conversation_id: conversation.display_id),
             params: { labels: %w[label3 label4] },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(response.body).to include('label3')
        expect(response.body).to include('label4')
        expect(conversation.reload.label_list).not_to include('label1', 'label2')
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/conversations/<id>/labels/add' do
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let(:canonical_label) { 'captain_revisar_pagamento' }
    let!(:existing_label) { create(:label, account: account, title: 'existing_label') }
    let!(:new_label) { create(:label, account: account, title: 'new_label') }
    let(:platform_label) { create(:label, account: account, title: canonical_label) }
    let!(:platform_bot) { create(:agent_bot, name: Chatwit::PlatformBot::BOT_NAME, account: nil) }

    before do
      Chatwit::PlatformBot.reset!
      platform_label
      conversation.update_labels([existing_label.title])
    end

    after { Chatwit::PlatformBot.reset! }

    def add_labels(bot: platform_bot, **params)
      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/labels/add",
           params: params,
           headers: { api_access_token: bot.access_token.token },
           as: :json
    end

    it 'adds existing account labels without replacing current labels' do
      add_labels(labels: [new_label.title])

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']).to contain_exactly(existing_label.title, new_label.title)
      expect(conversation.reload.label_list).to contain_exactly(existing_label.title, new_label.title)
    end

    it 'accepts canonical correlation and materializes an eligible trigger' do
      assistant = create(:captain_assistant, account: account)
      create(:captain_inbox, inbox: inbox, captain_assistant: assistant, mode: :phase2_only)

      with_modified_env CAPTAIN_PAYMENT_PHASE2_ENABLED: 'true', CAPTAIN_PAYMENT_PHASE2_INBOX_IDS: inbox.id.to_s do
        add_labels(labels: [canonical_label], payment_context: { id: 'ctx_1', version: 4 })
      end

      expect(response).to have_http_status(:success)
      expect(Captain::PaymentReviewTrigger.find_by!(conversation: conversation))
        .to have_attributes(payment_context_id: 'ctx_1', payment_context_version: 4, state: 'eligible')
    end

    it 'rejects any other global agent bot' do
      other_bot = create(:agent_bot, account: nil)

      add_labels(bot: other_bot, labels: [new_label.title])

      expect(response).to have_http_status(:unauthorized)
      expect(conversation.reload.label_list).to contain_exactly(existing_label.title)
    end

    it 'rejects a normal authenticated user' do
      agent = create(:user, account: account, role: :agent)
      create(:inbox_member, inbox: inbox, user: agent)

      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/labels/add",
           params: { labels: [new_label.title] },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects labels that do not belong to the current account' do
      foreign_label = create(:label, title: 'foreign_label')

      add_labels(labels: [foreign_label.title])

      expect(response).to have_http_status(:unprocessable_entity)
      expect(conversation.reload.label_list).to contain_exactly(existing_label.title)
    end

    it 'does not resolve a conversation from another account' do
      foreign_conversation = create(:conversation)
      foreign_conversation.update!(display_id: conversation.display_id + 1000)

      post "/api/v1/accounts/#{account.id}/conversations/#{foreign_conversation.display_id}/labels/add",
           params: { labels: [new_label.title] },
           headers: { api_access_token: platform_bot.access_token.token },
           as: :json

      expect(response).to have_http_status(:not_found)
      expect(foreign_conversation.reload.label_list).to be_empty
    end

    it 'rejects an empty label list and malformed payment correlation' do
      add_labels(labels: [])
      expect(response).to have_http_status(:unprocessable_entity)

      add_labels(labels: [canonical_label], payment_context: { id: 'ctx_1', version: 0 })
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns a stable conflict while canonical automation is disabled' do
      with_modified_env CAPTAIN_PAYMENT_PHASE2_ENABLED: 'false', CAPTAIN_PAYMENT_PHASE2_INBOX_IDS: inbox.id.to_s do
        add_labels(labels: [canonical_label])
      end

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['code']).to eq('phase2_disabled')
      expect(conversation.reload.label_list).not_to include(canonical_label)
    end
  end
end
