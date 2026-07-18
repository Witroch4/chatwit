# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Chatwit::AudioTranscriptionService do
  describe '.resolved_model' do
    it 'resolves the configured transcription alias through the canonical catalog' do
      allow(described_class).to receive(:model).and_return('witdev_antigravity/gemini-3.1-pro-low')
      expect(Chatwit::LlmProxy).to receive(:resolve_model!)
        .with('witdev_antigravity/gemini-3.1-pro-low')
        .and_return('witdev_antigravity/gemini-3.1-pro-low')

      expect(described_class.resolved_model).to eq('witdev_antigravity/gemini-3.1-pro-low')
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
      expect(service).not_to receive(:encode_audio)
      expect(HTTParty).not_to receive(:post)

      expect(service.perform).to eq(error: 'alias unavailable')
    end

    it 'memoizes the resolved alias and uses it in the request body' do
      allow(described_class).to receive(:model).and_return('witdev_antigravity/configured')
      expect(Chatwit::LlmProxy).to receive(:resolve_model!)
        .once
        .with('witdev_antigravity/configured')
        .and_return('witdev_antigravity/canonical')
      allow(service).to receive(:encode_audio).and_return('encoded-audio')
      allow(attachment).to receive(:update!)
      response = instance_double(HTTParty::Response, success?: true,
                                                     parsed_response: { 'choices' => [{ 'message' => { 'content' => 'texto' } }] })
      expect(HTTParty).to receive(:post) do |_url, options|
        expect(JSON.parse(options.fetch(:body)).fetch('model')).to eq('witdev_antigravity/canonical')
        response
      end

      expect(service.perform).to eq(success: true, transcriptions: 'texto')
    end

    it 'keeps the audio transport guard after canonical resolution' do
      allow(Chatwit::LlmProxy).to receive(:resolve_model!).and_return('witdev/model-without-audio')
      expect(HTTParty).not_to receive(:post)

      expect(service.perform).to eq(error: 'model witdev/model-without-audio does not support audio (use witdev_antigravity/*)')
    end
  end
end
