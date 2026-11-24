# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Chatwit::AudioTranscriptionService do
  describe '.resolved_model' do
    it 'resolves the configured transcription alias through the canonical catalog' do
      allow(described_class).to receive(:model).and_return('gpt-4o-transcribe')
      expect(Chatwit::LlmProxy).to receive(:resolve_model!)
        .with('gpt-4o-transcribe')
        .and_return('gpt-4o-transcribe')

      expect(described_class.resolved_model).to eq('gpt-4o-transcribe')
    end
  end

  describe '#perform' do
    let(:attachment) { instance_double(Attachment, id: 123, meta: nil) }
    let(:service) { described_class.new(attachment: attachment) }

    before do
      allow(described_class).to receive(:available?).and_return(true)
    end

    it 'fails before encoding or HTTP when the alias is absent from the operational catalog' do
      allow(Chatwit::LlmProxy).to receive(:resolve_model!)
        .and_raise(Chatwit::LlmProxy::ModelUnavailableError, 'alias unavailable')
      expect(service).not_to receive(:read_mp3)
      expect(HTTParty).not_to receive(:post)

      expect(service.perform).to eq(error: 'alias unavailable')
    end

    it 'memoizes the resolved alias and uses it in the request body' do
      allow(described_class).to receive(:model).and_return('gemini-configured')
      expect(Chatwit::LlmProxy).to receive(:resolve_model!)
        .once
        .with('gemini-configured')
        .and_return('gemini-canonical')
      allow(service).to receive(:read_mp3).and_return('mp3-bytes')
      allow(attachment).to receive(:update!)
      response = instance_double(HTTParty::Response, success?: true,
                                                     parsed_response: { 'choices' => [{ 'message' => { 'content' => 'texto' } }] })
      expect(HTTParty).to receive(:post) do |_url, options|
        expect(JSON.parse(options.fetch(:body)).fetch('model')).to eq('gemini-canonical')
        response
      end

      expect(service.perform).to eq(success: true, transcriptions: 'texto')
    end

    it 'keeps the audio transport guard after canonical resolution' do
      allow(Chatwit::LlmProxy).to receive(:resolve_model!).and_return('witdev/model-without-audio')
      expect(HTTParty).not_to receive(:post)

      expect(service.perform).to eq(error: 'model witdev/model-without-audio does not support audio (use gpt-transcribe or gemini-*)')
    end

    it 'sends OpenAI transcription models to the audio transcriptions endpoint as multipart mp3' do
      allow(Chatwit::LlmProxy).to receive_messages(resolve_model!: 'gpt-4o-transcribe', api_base: 'http://litellm.test/v1',
                                                   api_key: 'chave-teste')
      allow(service).to receive(:read_mp3).and_return('mp3-bytes')
      allow(attachment).to receive(:update!)
      expect(HTTParty).not_to receive(:post)
      # Net::HTTP streams the multipart body, so WebMock sees no body: check the route,
      # auth and content type here and the form fields in the next example.
      request = stub_request(:post, 'http://litellm.test/v1/audio/transcriptions')
                .with(headers: { 'Authorization' => 'Bearer chave-teste' }) do |req|
                  req.headers['Content-Type'].to_s.start_with?('multipart/form-data')
                end
                .to_return(status: 200, body: { text: ' Olá, bom dia. ' }.to_json, headers: { 'Content-Type' => 'application/json' })

      expect(service.perform).to eq(success: true, transcriptions: 'Olá, bom dia.')
      expect(request).to have_been_requested.once
    end

    it 'builds the transcription form with the resolved model, Portuguese, plain json and the mp3 file' do
      allow(Chatwit::LlmProxy).to receive(:resolve_model!).and_return('gpt-transcribe')

      form = service.send(:transcription_form, 'mp3-bytes')

      expect(form[0]).to eq(%w[model gpt-transcribe])
      expect(form[1]).to eq(%w[language pt])
      # gpt-transcribe refuses the proxy's default verbose_json.
      expect(form[2]).to eq(%w[response_format json])
      expect(form[3][0]).to eq('file')
      expect(form[3][1].read).to eq('mp3-bytes')
      expect(form[3][2]).to eq(filename: 'audio.mp3', content_type: 'audio/mpeg')
    end

    it 'sends long audio to the long-audio Gemini model through chat even when gpt-4o-transcribe is configured' do
      allow(described_class).to receive(:model).and_return('gpt-4o-transcribe')
      allow(Chatwit::LlmProxy).to receive(:resolve_model!) { |name| name }
      allow(service).to receive(:read_mp3).and_return('x' * (described_class::OPENAI_MAX_AUDIO_BYTES + 1))
      allow(attachment).to receive(:update!)
      response = instance_double(HTTParty::Response, success?: true,
                                                     parsed_response: { 'choices' => [{ 'message' => { 'content' => 'longo' } }] })
      expect(HTTParty).to receive(:post) do |url, options|
        expect(url).to end_with('/chat/completions')
        expect(JSON.parse(options.fetch(:body)).fetch('model')).to eq(described_class::LONG_AUDIO_MODEL)
        response
      end

      expect(service.perform).to eq(success: true, transcriptions: 'longo')
    end

    it 'falls back to the Gemini model when the OpenAI transcription fails' do
      allow(Chatwit::LlmProxy).to receive(:resolve_model!) { |name| name }
      allow(Chatwit::LlmProxy).to receive_messages(api_base: 'http://litellm.test/v1', api_key: 'chave-teste')
      allow(described_class).to receive(:model).and_return('gpt-transcribe')
      allow(service).to receive(:read_mp3).and_return('mp3-bytes')
      allow(attachment).to receive(:update!)
      stub_request(:post, 'http://litellm.test/v1/audio/transcriptions').to_return(status: 503, body: 'upstream down')
      response = instance_double(HTTParty::Response, success?: true,
                                                     parsed_response: { 'choices' => [{ 'message' => { 'content' => 'pelo gemini' } }] })
      expect(HTTParty).to receive(:post) do |_url, options|
        expect(JSON.parse(options.fetch(:body)).fetch('model')).to eq(described_class::LONG_AUDIO_MODEL)
        response
      end

      expect(service.perform).to eq(success: true, transcriptions: 'pelo gemini')
    end

    it 'keeps the proxy error body in the failure message' do
      allow(Chatwit::LlmProxy).to receive_messages(resolve_model!: 'gpt-4o-transcribe', api_base: 'http://litellm.test/v1',
                                                   api_key: 'chave-teste')
      allow(service).to receive(:read_mp3).and_return('mp3-bytes')
      stub_request(:post, 'http://litellm.test/v1/audio/transcriptions')
        .to_return(status: 400, body: '{"error":{"message":"audio too long"}}')
      failed = instance_double(HTTParty::Response, success?: false, code: 502, body: 'gemini down')
      allow(HTTParty).to receive(:post).and_return(failed)

      error = service.perform[:error]
      expect(error).to include('HTTP 400').and include('audio too long')
      expect(error).to include('HTTP 502').and include('gemini down')
    end
  end

  describe '.audio_capable?' do
    it 'accepts the OpenAI transcription models and the Gemini aliases only' do
      expect(described_class.audio_capable?('gpt-transcribe')).to be(true)
      expect(described_class.audio_capable?('gpt-4o-transcribe')).to be(true)
      expect(described_class.audio_capable?('gpt-4o-mini-transcribe')).to be(true)
      expect(described_class.audio_capable?('gemini-3.5-transcribe')).to be(true)
      expect(described_class.audio_capable?('gpt-6-luna')).to be(false)
      expect(described_class.audio_capable?('claude-haiku-5-5')).to be(false)
    end
  end
end
