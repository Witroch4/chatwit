require 'rails_helper'
require 'vips'

RSpec.describe 'Stickers API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def png_upload
    bytes = Vips::Image.black(300, 300).add([0, 0, 255]).cast(:uchar).copy(interpretation: :srgb).write_to_buffer('.png')
    file = Tempfile.new(['s', '.png'])
    file.binmode
    file.write(bytes)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, 'image/png')
  end

  describe 'POST /api/v1/accounts/{account}/stickers' do
    it 'creates a sticker from an uploaded image' do
      expect do
        post "/api/v1/accounts/#{account.id}/stickers",
             params: { file: png_upload }, headers: agent.create_new_auth_token
      end.to change(Sticker, :count).by(1)
      expect(response).to have_http_status(:success)
    end
  end

  describe 'POST /api/v1/accounts/{account}/stickers/{id}/send_sticker' do
    let!(:whatsapp_channel) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false) }
    let(:conversation) { create(:conversation, account: account, inbox: whatsapp_channel.inbox) }
    let(:sticker) { Stickers::ConverterService.new(account: account, user: agent, file: png_upload).perform }

    it 'creates an outgoing sticker message in the conversation' do
      expect do
        post "/api/v1/accounts/#{account.id}/stickers/#{sticker.id}/send_sticker",
             params: { conversation_id: conversation.display_id }, headers: agent.create_new_auth_token
      end.to change { conversation.messages.where(content_type: 'sticker').count }.by(1)
      expect(response).to have_http_status(:success)
    end
  end
end
