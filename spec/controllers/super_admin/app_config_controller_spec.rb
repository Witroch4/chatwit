require 'rails_helper'

RSpec.describe 'Super Admin Application Config API', type: :request do
  let(:super_admin) { create(:super_admin) }

  describe 'GET /super_admin/app_config' do
    context 'when it is an unauthenticated super admin' do
      it 'returns unauthorized' do
        get '/super_admin/app_config'
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated super admin' do
      let!(:config) { create(:installation_config, { name: 'FB_APP_ID', value: 'TESTVALUE' }) }

      it 'shows the app_config page' do
        sign_in(super_admin, scope: :super_admin)
        get '/super_admin/app_config?config=facebook'
        expect(response).to have_http_status(:success)
        expect(response.body).to include(config.value)
      end

      it 'builds the WitDev selects only from operational models without injecting the recommended transcription alias' do
        allow(Chatwit::LlmProxy).to receive(:operational_models).and_return(
          [{ 'value' => 'gemini-audio-canonical', 'label' => 'Gemini Audio', 'provider_label' => 'Google' }]
        )

        sign_in(super_admin, scope: :super_admin)
        get '/super_admin/app_config?config=captain'

        document = Nokogiri::HTML(response.body)
        model_values = document.css('select[name="app_config[CAPTAIN_WITDEV_MODEL]"] option').pluck('value')
        transcription_values = document.css('select[name="app_config[CAPTAIN_WITDEV_TRANSCRIPTION_MODEL]"] option').pluck('value')

        expect(model_values).to eq(['gemini-audio-canonical'])
        expect(transcription_values).to eq(['gemini-audio-canonical'])
        expect(transcription_values).not_to include(Chatwit::AudioTranscriptionService::RECOMMENDED_MODEL)
      end

      it 'renders empty WitDev selects when the operational catalog is unavailable' do
        allow(Chatwit::LlmProxy).to receive(:operational_models).and_return([])

        sign_in(super_admin, scope: :super_admin)
        get '/super_admin/app_config?config=captain'

        document = Nokogiri::HTML(response.body)
        expect(document.at_css('select[name="app_config[CAPTAIN_WITDEV_MODEL]"]')).to be_present
        expect(document.at_css('select[name="app_config[CAPTAIN_WITDEV_TRANSCRIPTION_MODEL]"]')).to be_present
      end
    end
  end

  describe 'POST /super_admin/app_config' do
    context 'when it is an unauthenticated super admin' do
      it 'returns unauthorized' do
        post '/super_admin/app_config', params: { app_config: { TESTKEY: 'TESTVALUE' } }
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an aunthenticated super admin' do
      it 'shows the app_config page' do
        sign_in(super_admin, scope: :super_admin)
        post '/super_admin/app_config?config=facebook', params: { app_config: { FB_APP_ID: 'FB_APP_ID' } }

        expect(response).to have_http_status(:found)
        expect(response).to redirect_to(super_admin_settings_path)

        config = GlobalConfig.get('FB_APP_ID')
        expect(config['FB_APP_ID']).to eq('FB_APP_ID')
      end

      it 'rejects an unauthorized changed WitDev model and preserves the previous value' do
        config = create(:installation_config, name: 'CAPTAIN_WITDEV_MODEL', value: 'witdev/old')
        allow(Chatwit::LlmProxy).to receive(:resolve_model!).with('witdev/unauthorized')
                                                            .and_raise(Chatwit::LlmProxy::ModelUnavailableError, 'alias unavailable')

        sign_in(super_admin, scope: :super_admin)
        post '/super_admin/app_config?config=captain', params: { app_config: { CAPTAIN_WITDEV_MODEL: 'witdev/unauthorized' } }

        expect(response).to redirect_to('/super_admin/app_config?config=captain')
        expect(flash[:alert]).to include('alias unavailable')
        expect(config.reload.value).to eq('witdev/old')
      end

      it 'rejects a transcription alias that cannot transport audio after canonical resolution' do
        config = create(:installation_config, name: 'CAPTAIN_WITDEV_TRANSCRIPTION_MODEL', value: 'gemini-audio-old')
        allow(Chatwit::LlmProxy).to receive(:resolve_model!).with('witdev/model-without-audio').and_return('witdev/model-without-audio')

        sign_in(super_admin, scope: :super_admin)
        post '/super_admin/app_config?config=captain',
             params: { app_config: { CAPTAIN_WITDEV_TRANSCRIPTION_MODEL: 'witdev/model-without-audio' } }

        expect(response).to redirect_to('/super_admin/app_config?config=captain')
        expect(flash[:alert]).to include('does not support audio')
        expect(config.reload.value).to eq('gemini-audio-old')
      end

      it 'does not revalidate an unchanged model submitted by the generic form' do
        create(:installation_config, name: 'CAPTAIN_WITDEV_MODEL', value: 'witdev/current')
        expect(Chatwit::LlmProxy).not_to receive(:resolve_model!)

        sign_in(super_admin, scope: :super_admin)
        post '/super_admin/app_config?config=captain', params: { app_config: { CAPTAIN_WITDEV_MODEL: 'witdev/current' } }

        expect(response).to redirect_to(super_admin_settings_path)
      end
    end
  end
end
