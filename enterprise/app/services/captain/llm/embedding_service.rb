class Captain::Llm::EmbeddingService
  include Integrations::LlmInstrumentation

  class EmbeddingsError < StandardError; end

  def initialize(account_id: nil)
    Llm::Config.initialize!
    @account_id = account_id
    @embedding_model = InstallationConfig.find_by(name: 'CAPTAIN_EMBEDDING_MODEL')&.value.presence || LlmConstants::DEFAULT_EMBEDDING_MODEL
  end

  def self.embedding_model
    InstallationConfig.find_by(name: 'CAPTAIN_EMBEDDING_MODEL')&.value.presence || LlmConstants::DEFAULT_EMBEDDING_MODEL
  end

  def get_embedding(content, model: @embedding_model)
    return [] if content.blank?

    instrument_embedding_call(instrumentation_params(content, model)) do
      embed_vectors(content, model)
    end
  rescue RubyLLM::Error => e
    Rails.logger.error "Embedding API Error: #{e.message}"
    raise EmbeddingsError, "Failed to create an embedding: #{e.message}"
  end

  private

  # Chatwit: the WitDev route repoints the global OpenAI config at the LiteLLM
  # proxy, which only covers chat — embeddings stay pinned to the legacy keys.
  def embed_vectors(content, model)
    return RubyLLM.embed(content, model: model).vectors unless Chatwit::LlmProxy.enabled?

    api_key = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
    api_base = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value.presence&.chomp('/')
    Llm::Config.with_api_key(api_key, api_base: api_base) do |context|
      context.embed(content, model: model).vectors
    end
  end

  def instrumentation_params(content, model)
    {
      span_name: 'llm.captain.embedding',
      model: model,
      input: content,
      feature_name: 'embedding',
      account_id: @account_id
    }
  end
end
