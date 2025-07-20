require 'google/cloud/dialogflow/v2'
require 'google/protobuf'

class Integrations::Dialogflow::ProcessorService < Integrations::BotProcessorService
  pattr_initialize [:event_name!, :hook!, :event_data!]

  private

  def message_content(message)
    # TODO: might needs to change this to a way that we fetch the updated value from event data instead
    # cause the message.updated event could be that that the message was deleted

    return message.content_attributes['submitted_values']&.first&.dig('value') if event_name == 'message.updated'

    message.content
  end

  def get_response(session_id, message_content)
    if hook.settings['credentials'].blank?
      Rails.logger.warn "Account: #{hook.try(:account_id)} Hook: #{hook.id} credentials are not present." && return
    end

    configure_dialogflow_client_defaults
    detect_intent(session_id, message_content)
  rescue Google::Cloud::PermissionDeniedError => e
    Rails.logger.warn "DialogFlow Error: (account-#{hook.try(:account_id)}, hook-#{hook.id}) #{e.message}"
    hook.prompt_reauthorization!
    hook.disable
  end

  def process_response(message, response)
    fulfillment_messages = response.query_result['fulfillment_messages']
    fulfillment_messages.each do |fulfillment_message|
      content_params = generate_content_params(fulfillment_message)
      if content_params['action'].present?
        process_action(message, content_params['action'])
      else
        create_conversation(message, content_params)
      end
    end
  end

  def generate_content_params(fulfillment_message)
    text_response = fulfillment_message['text'].to_h
    content_params = { content: text_response[:text].first } if text_response[:text].present?
    content_params ||= fulfillment_message['payload'].to_h
    content_params
  end

  def create_conversation(message, content_params)
    return if content_params.blank?

    conversation = message.conversation
    conversation.messages.create!(
      content_params.merge(
        {
          message_type: :outgoing,
          account_id: conversation.account_id,
          inbox_id: conversation.inbox_id
        }
      )
    )
  end

  def configure_dialogflow_client_defaults
    ::Google::Cloud::Dialogflow::V2::Sessions::Client.configure do |config|
      config.timeout = 10.0
      config.credentials = hook.settings['credentials']
      config.endpoint = dialogflow_endpoint
    end
  end

  def normalized_region
    region = hook.settings['region'].to_s.strip
    (region.presence || 'global')
  end

  def dialogflow_endpoint
    region = normalized_region
    return 'dialogflow.googleapis.com' if region == 'global'

    "#{region}-dialogflow.googleapis.com"
  end

  ##################################################################
  # UTILITÁRIO – converte Hash simples em google.protobuf.Struct
  ##################################################################
  def hash_to_struct(hash)
    fields = hash.each_with_object({}) do |(k, v), h|
      h[k.to_s] =
        case v
        when TrueClass, FalseClass
          Google::Protobuf::Value.new(bool_value: v)
        when Numeric
          Google::Protobuf::Value.new(number_value: v)
        when Hash
          Google::Protobuf::Value.new(struct_value: hash_to_struct(v))
        else
          Google::Protobuf::Value.new(string_value: v.to_s)
        end
    end

    Google::Protobuf::Struct.new(fields: fields)
  end

  ##################################################################
  # ENVIO A DIALOGFLOW
  ##################################################################
  def detect_intent(session_id, message)
    client  = ::Google::Cloud::Dialogflow::V2::Sessions::Client.new
    session = build_session_path(session_id)

    # ---------- texto que o usuário enviou ------------
    query_input = {
      text: {
        text:          message,
        language_code: 'pt-BR'
      }
    }

    # ---------- monta payload extra se Socialwise ativo ------------
    query_params = nil
    if socialwise_chatwit_enabled?
      extra_payload = build_whatsapp_payload_data
      unless extra_payload.blank?
        Rails.logger.info "[SOCIALWISE] Enviando payload oculto: #{extra_payload.inspect}"
        query_params = { payload: hash_to_struct(extra_payload) }
      end
    end

    # ---------- request final --------------------------
    request = {
      session:     session,
      query_input: query_input
    }
    request[:query_params] = query_params if query_params

    client.detect_intent(request)   # <-- faz a chamada
  end

  def build_session_path(session_id)
    project_id = hook.settings['project_id']
    region = normalized_region

    if region == 'global'
      "projects/#{project_id}/agent/sessions/#{session_id}"
    else
      "projects/#{project_id}/locations/#{region}/agent/sessions/#{session_id}"
    end
  end

  def socialwise_chatwit_enabled?
    # Procura por hook Socialwise ativo
    socialwise_hook = hook.account.hooks.find_by(app_id: 'socialwise_chatwit', status: 'enabled')
    
    if socialwise_hook
      # Verifica se o settings tem enabled = true
      enabled = socialwise_hook.settings&.dig('enabled')
      Rails.logger.info "[SOCIALWISE] Hook encontrado. Settings: #{socialwise_hook.settings.inspect}, enabled: #{enabled}"
      return enabled == true || enabled == 'true'
    else
      Rails.logger.info "[SOCIALWISE] Nenhum hook Socialwise encontrado"
      return false
    end
  end

  def build_whatsapp_payload_data
    message = event_data[:message]
    conversation = message.conversation
    inbox = conversation.inbox
    contact = conversation.contact
    
    Rails.logger.info "[SOCIALWISE] Inbox type: #{inbox.channel_type}"
    Rails.logger.info "[SOCIALWISE] Contact custom_attributes: #{contact.custom_attributes.inspect}"
    
    # Verifica se é um canal WhatsApp (pode ser diferente)
    is_whatsapp_channel = inbox.channel_type == 'Channel::Whatsapp' || 
                         inbox.channel.class.name == 'Channel::Whatsapp' ||
                         message.source_id&.include?('WAID')
    
    Rails.logger.info "[SOCIALWISE] É canal WhatsApp: #{is_whatsapp_channel}"
    
    # Extrair API_KEY do WhatsApp se disponível
    whatsapp_api_key = nil
    if is_whatsapp_channel && inbox.channel.respond_to?(:provider_config)
      begin
        whatsapp_api_key = inbox.channel.provider_config&.dig('api_key')
        Rails.logger.info "[SOCIALWISE] WhatsApp API key extracted: #{whatsapp_api_key.present? ? 'Present' : 'Not found'}"
      rescue => e
        Rails.logger.error "[SOCIALWISE] Error extracting WhatsApp API key: #{e.class}: #{e.message}"
      end
    end
    
    # =======================================================
    # PAYLOAD EXPANDIDO - DADOS COMPLETOS DO CHATWOOT
    # =======================================================
    payload = {
      # === IDENTIFICADORES WHATSAPP ===
      "wamid" => message.source_id,
      "whatsapp_id" => message.source_id,
      
      # === DADOS DO CONTATO ===
      "contact_name" => contact.name,
      "contact_phone" => contact.phone_number,
      "contact_email" => contact.email,
      "contact_identifier" => contact.identifier,
      "contact_id" => contact.id,
      
      # === CUSTOM ATTRIBUTES (DADOS PERSONALIZADOS) ===
      **contact.custom_attributes.to_h,
      
      # === DADOS DA CONVERSA ===
      "conversation_id" => conversation.id,
      "conversation_status" => conversation.status,
      "conversation_assignee_id" => conversation.assignee_id,
      "conversation_created_at" => conversation.created_at&.iso8601,
      "conversation_updated_at" => conversation.updated_at&.iso8601,
      
      # === DADOS DO INBOX ===
      "inbox_id" => inbox.id,
      "inbox_name" => inbox.name,
      "channel_type" => inbox.channel_type,
      
      # === DADOS DA CONTA ===
      "account_id" => conversation.account_id,
      "account_name" => conversation.account.name,
      
      # === DADOS DA MENSAGEM ===
      "message_id" => message.id,
      "message_content" => message.content,
      "message_type" => message.message_type,
      "message_created_at" => message.created_at&.iso8601,
      "message_content_type" => message.content_type,
      
      # === DADOS DO CANAL ===
      "contact_source" => conversation.contact_inbox.source_id,
      
      # === API KEY DO WHATSAPP ===
      "whatsapp_api_key" => whatsapp_api_key,
      
      # === METADADOS DA INTEGRAÇÃO ===
      "socialwise_active" => true,
      "is_whatsapp_channel" => is_whatsapp_channel,
      "has_whatsapp_api_key" => whatsapp_api_key.present?,
      "payload_version" => "2.0",
      "timestamp" => Time.current.iso8601
    }
    
    Rails.logger.info "[SOCIALWISE] Payload final construído: #{payload.inspect}"
    
    payload
  rescue => e
    Rails.logger.error "[SOCIALWISE] Erro ao construir payload: #{e.class}: #{e.message}"
    Rails.logger.error "[SOCIALWISE] Backtrace: #{e.backtrace.join('\n')}"
    
    # Payload de fallback com dados essenciais
    {
      "wamid" => message.source_id,
      "whatsapp_id" => message.source_id,
      "contact_name" => contact.name,
      **contact.custom_attributes.to_h,
      "socialwise_active" => true,
      "whatsapp_api_key" => nil,
      "has_whatsapp_api_key" => false,
      "error" => "Payload construction failed: #{e.class}: #{e.message}"
    }
  end
end
