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
    # Use shared SocialWise service to check if integration is active
    Integrations::Socialwise::WebhookEnhancerService.socialwise_active?(hook.account)
  end

  def build_whatsapp_payload_data
    # Use shared SocialWise service to get structured data
    message = event_data[:message]
    conversation = message.conversation
    contact = conversation.contact
    inbox = conversation.inbox
    
    # Create a webhook-like payload for the shared service
    webhook_payload = {
      message: message,
      conversation: conversation,
      contact: contact,
      inbox: inbox
    }
    
    # Get enhanced payload from shared service
    enhanced_payload = Integrations::Socialwise::WebhookEnhancerService.enhance_payload(webhook_payload, hook.account)
    socialwise_data = enhanced_payload['socialwise-chatwit']
    
    return {} unless socialwise_data
    
    # Convert nested structure to flat structure for Dialogflow backward compatibility
    flat_payload = {}
    
    # WhatsApp identifiers
    if socialwise_data['whatsapp_identifiers']
      flat_payload['wamid'] = socialwise_data['whatsapp_identifiers']['wamid']
      flat_payload['whatsapp_id'] = socialwise_data['whatsapp_identifiers']['whatsapp_id']
      flat_payload['contact_source'] = socialwise_data['whatsapp_identifiers']['contact_source']
    end
    
    # Contact data
    if socialwise_data['contact_data']
      flat_payload['contact_name'] = socialwise_data['contact_data']['name']
      flat_payload['contact_phone'] = socialwise_data['contact_data']['phone_number']
      flat_payload['contact_email'] = socialwise_data['contact_data']['email']
      flat_payload['contact_identifier'] = socialwise_data['contact_data']['identifier']
      flat_payload['contact_id'] = socialwise_data['contact_data']['id']
      
      # Merge custom attributes at root level for backward compatibility
      if socialwise_data['contact_data']['custom_attributes'].is_a?(Hash)
        flat_payload.merge!(socialwise_data['contact_data']['custom_attributes'])
      end
    end
    
    # Conversation data
    if socialwise_data['conversation_data']
      flat_payload['conversation_id'] = socialwise_data['conversation_data']['id']
      flat_payload['conversation_status'] = socialwise_data['conversation_data']['status']
      flat_payload['conversation_assignee_id'] = socialwise_data['conversation_data']['assignee_id']
      flat_payload['conversation_created_at'] = socialwise_data['conversation_data']['created_at']
      flat_payload['conversation_updated_at'] = socialwise_data['conversation_data']['updated_at']
    end
    
    # Message data
    if socialwise_data['message_data']
      flat_payload['message_id'] = socialwise_data['message_data']['id']
      flat_payload['message_content'] = socialwise_data['message_data']['content']
      flat_payload['message_type'] = socialwise_data['message_data']['message_type']
      flat_payload['message_created_at'] = socialwise_data['message_data']['created_at']
      flat_payload['message_content_type'] = socialwise_data['message_data']['content_type']
    end
    
    # Inbox data
    if socialwise_data['inbox_data']
      flat_payload['inbox_id'] = socialwise_data['inbox_data']['id']
      flat_payload['inbox_name'] = socialwise_data['inbox_data']['name']
      flat_payload['channel_type'] = socialwise_data['inbox_data']['channel_type']
    end
    
    # Account data
    if socialwise_data['account_data']
      flat_payload['account_id'] = socialwise_data['account_data']['id']
      flat_payload['account_name'] = socialwise_data['account_data']['name']
    end
    
    # WhatsApp API key and metadata
    flat_payload['whatsapp_api_key'] = socialwise_data['whatsapp_api_key']
    
    if socialwise_data['metadata']
      flat_payload['socialwise_active'] = socialwise_data['metadata']['socialwise_active']
      flat_payload['is_whatsapp_channel'] = socialwise_data['metadata']['is_whatsapp_channel']
      flat_payload['has_whatsapp_api_key'] = socialwise_data['metadata']['has_whatsapp_api_key']
      flat_payload['payload_version'] = socialwise_data['metadata']['payload_version']
      flat_payload['timestamp'] = socialwise_data['metadata']['timestamp']
    end
    
    Rails.logger.info "[SOCIALWISE] Dialogflow payload built using shared service: #{flat_payload.inspect}"
    
    flat_payload
  rescue => e
    Rails.logger.error "[SOCIALWISE] Error building Dialogflow payload: #{e.class}: #{e.message}"
    Rails.logger.error "[SOCIALWISE] Backtrace: #{e.backtrace.join('\n')}"
    
    # Fallback payload with essential data
    message = event_data[:message]
    conversation = message.conversation
    contact = conversation.contact
    
    {
      "wamid" => message.source_id,
      "whatsapp_id" => message.source_id,
      "contact_name" => contact.name,
      **(contact.custom_attributes.to_h rescue {}),
      "socialwise_active" => true,
      "whatsapp_api_key" => nil,
      "has_whatsapp_api_key" => false,
      "error" => "Payload construction failed: #{e.class}: #{e.message}"
    }
  end
end
