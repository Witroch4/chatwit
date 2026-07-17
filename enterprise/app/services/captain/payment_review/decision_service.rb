# Dedicated phase-2 decision path. Never reuses the continuous Captain
# runner/tools: the LLM receives only the operator prompt, sanitized history,
# boolean capabilities and the authorized preset names (never amounts, URLs,
# NSUs or keys), and must answer with exactly one closed-schema action.
class Captain::PaymentReview::DecisionService
  class DecisionFailed < StandardError; end

  MAX_ATTEMPTS = 2
  REQUEST_TIMEOUT = 30

  STRUCTURAL_GUARDRAILS = <<~GUARDRAILS.freeze
    Você é o revisor de pagamento (fase 2) de uma conversa de atendimento.
    A análise, a cobrança e o botão de pagamento JÁ foram enviados ao lead antes de você acordar.
    Regras invioláveis, acima de qualquer instrução do operador:
    - Nunca invente valores, descontos, links ou chaves de pagamento.
    - Nunca escreva URLs, códigos de fatura ou identificadores de cobrança na resposta.
    - Execute no máximo UMA ação por decisão.
    - Responda SOMENTE com um objeto JSON: {"action": "...", "response": null, "reason_code": "...", "preset_id": null}.
    - Ações válidas: no_action, reply, send_cta, send_pix_key, send_status, send_payment_preset, handoff_required.
    - "reply" exige "response" com texto útil; todas as outras ações exigem "response": null.
    - "send_payment_preset" exige "preset_id" com o id de um favorito autorizado listado abaixo.
    - Saudações, agradecimentos ou ausência de pergunta nova: use no_action.
    - Fora do escopo de pagamento/dúvidas cobertas: use handoff_required.
  GUARDRAILS

  def initialize(run:, context:)
    @run = run
    @context = context
    @conversation = run.conversation
    @captain_inbox = @conversation.inbox.captain_inbox
  end

  def call
    messages = build_messages
    failure = nil

    MAX_ATTEMPTS.times do
      raw = complete(messages: messages_with_correction(messages, failure), model: model)
      begin
        decision = Captain::PaymentReview::DecisionSchema.parse(raw)
        validate_preset!(decision)
        validate_reply!(decision)
        account.increment_response_usage
        return decision
      rescue Captain::PaymentReview::DecisionSchema::InvalidDecisionError => e
        failure = e.message
      end
    end

    raise DecisionFailed, failure.to_s
  end

  private

  attr_reader :run, :context, :conversation, :captain_inbox

  def account
    conversation.account
  end

  def model
    captain_inbox&.phase2_model.presence ||
      proxy_model.presence ||
      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence ||
      LlmConstants::DEFAULT_MODEL
  end

  def proxy_model
    Chatwit::LlmProxy.model if Chatwit::LlmProxy.enabled?
  end

  def build_messages
    [{ role: 'system', content: system_prompt }] + history_messages
  end

  def system_prompt
    [
      STRUCTURAL_GUARDRAILS,
      "Instruções do operador:\n#{operator_prompt}",
      capabilities_block,
      presets_block
    ].join("\n\n")
  end

  def operator_prompt
    captain_inbox&.phase2_prompt_or_default.presence || Captain::PaymentReview::DEFAULT_PROMPT
  end

  def capabilities_block
    flags = capability_flags.map { |name, enabled| "#{name}=#{enabled ? 'sim' : 'não'}" }
    status = context&.status.presence || 'sem cobrança corrente'
    "Estado reduzido da cobrança: #{status}.\nCapacidades disponíveis: #{flags.join(', ')}."
  end

  def capability_flags
    return { send_cta: false, send_pix_key: local_pix_key.present?, send_status: false } if context.nil?

    {
      send_cta: context.can_send_cta,
      send_pix_key: local_pix_key.present? || context.has_official_pix_key,
      send_status: context.can_send_status
    }
  end

  def presets_block
    presets = authorized_presets
    return 'Favoritos de pagamento autorizados: nenhum.' if presets.empty?

    lines = presets.map { |preset| "- preset_id #{preset.id}: #{preset.name}" }
    "Favoritos de pagamento autorizados (envio via send_payment_preset):\n#{lines.join("\n")}"
  end

  def authorized_presets
    ids = Array(captain_inbox&.phase2_payment_preset_ids).map(&:to_i)
    return [] if ids.empty?

    account.payment_presets.where(id: ids).select(:id, :name)
  end

  def local_pix_key
    captain_inbox&.phase2_pix_key
  end

  def history_messages
    Captain::PaymentReview::HistoryProjector.new(run).project.map do |entry|
      { role: entry[:role] == 'lead' ? 'user' : 'assistant', content: entry[:content] }
    end
  end

  def messages_with_correction(messages, failure)
    return messages if failure.blank?

    messages + [{ role: 'system', content: "A resposta anterior era inválida (#{failure}). Responda novamente seguindo o schema." }]
  end

  def validate_preset!(decision)
    return unless decision.payment_preset?

    allowed = Array(captain_inbox&.phase2_payment_preset_ids).map(&:to_i)
    return if allowed.include?(decision.preset_id) && account.payment_presets.exists?(id: decision.preset_id)

    raise Captain::PaymentReview::DecisionSchema::InvalidDecisionError,
          'preset_id is not in the authorized favorites'
  end

  def validate_reply!(decision)
    return unless decision.reply?
    return if Captain::PaymentReview::ReplyLeakValidator.new(operator_prompt: captain_inbox&.phase2_prompt).valid?(decision.response)

    raise Captain::PaymentReview::DecisionSchema::InvalidDecisionError,
          'reply leaks unauthorized financial content'
  end

  def complete(messages:, model:)
    client = OpenAI::Client.new(
      access_token: llm_api_key,
      uri_base: llm_api_base,
      request_timeout: REQUEST_TIMEOUT
    )
    response = client.chat(
      parameters: {
        model: model,
        messages: messages,
        temperature: 0,
        response_format: { type: 'json_object' }
      }
    )
    response.dig('choices', 0, 'message', 'content').to_s
  end

  def llm_api_base
    return Chatwit::LlmProxy.api_base if Chatwit::LlmProxy.enabled?

    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value.presence
  end

  def llm_api_key
    return Chatwit::LlmProxy.api_key if Chatwit::LlmProxy.enabled?

    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
  end
end
