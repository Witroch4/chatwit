# frozen_string_literal: true

class Integrations::Socialwise::WebhookEnhancerService
  class << self
    # Enhances webhook payload with SocialWise data if the integration is active
    # @param payload [Hash] The original webhook payload
    # @param account [Account] The account to check for SocialWise integration
    # @return [Hash] Enhanced payload with socialwise-chatwit data or original payload
    def enhance_payload(payload, account)
      return payload unless socialwise_active?(account)

      enhanced_payload = payload.dup
      enhanced_payload['socialwise-chatwit'] = build_socialwise_data(payload, account)
      enhanced_payload
    rescue => e
      Rails.logger.error "[SOCIALWISE] Enhancement failed: #{e.message}"
      Rails.logger.error "[SOCIALWISE] Backtrace: #{e.backtrace.join('\n')}"
      payload # Return original payload on error
    end

    # Checks if SocialWise integration is enabled for the given account
    # @param account [Account] The account to check
    # @return [Boolean] true if SocialWise is active, false otherwise
    def socialwise_active?(account)
      hook = account.hooks.find_by(app_id: 'socialwise_chatwit', status: 'enabled')
      return false unless hook

      enabled = hook.settings&.dig('enabled')
      enabled == true || enabled == 'true'
    rescue => e
      Rails.logger.error "[SOCIALWISE] State check failed: #{e.message}"
      false
    end

    private

    # Builds the socialwise-chatwit data structure from the webhook payload
    # @param payload [Hash] The webhook payload
    # @param account [Account] The account
    # @return [Hash] The socialwise-chatwit data structure
    def build_socialwise_data(payload, account)
      Rails.logger.info "[SOCIALWISE] Building socialwise-chatwit data for account #{account&.id}"
      
      # Extract core objects from payload with error handling
      message = safe_extract_message_from_payload(payload)
      conversation = safe_extract_conversation_from_payload(payload)
      contact = safe_extract_contact_from_payload(payload)
      inbox = safe_extract_inbox_from_payload(payload)

      # Build comprehensive data structure with individual error handling
      data = {}
      
      data['whatsapp_identifiers'] = build_whatsapp_identifiers(message, contact)
      data['contact_data'] = build_contact_data(contact)
      data['conversation_data'] = build_conversation_data(conversation)
      data['message_data'] = build_message_data(message)
      data['inbox_data'] = build_inbox_data(inbox)
      data['account_data'] = build_account_data(account)
      data['metadata'] = build_metadata(inbox)
      data['whatsapp_api_key'] = extract_whatsapp_api_key(inbox)
      
      Rails.logger.info "[SOCIALWISE] Successfully built socialwise-chatwit data"
      data
    rescue => e
      Rails.logger.error "[SOCIALWISE] Critical error building socialwise-chatwit data: #{e.class}: #{e.message}"
      Rails.logger.error "[SOCIALWISE] Backtrace: #{e.backtrace.join('\n')}"
      Rails.logger.error "[SOCIALWISE] Payload keys: #{payload&.keys&.inspect}"
      Rails.logger.error "[SOCIALWISE] Account ID: #{account&.id}"
      
      # Return comprehensive fallback data structure
      build_fallback_data_structure(e, account)
    end

    # Safe extraction methods with error handling
    
    # Extract message object from payload with error handling
    def safe_extract_message_from_payload(payload)
      extract_message_from_payload(payload)
    rescue => e
      Rails.logger.error "[SOCIALWISE] Error extracting message from payload: #{e.class}: #{e.message}"
      nil
    end

    # Extract conversation object from payload with error handling
    def safe_extract_conversation_from_payload(payload)
      extract_conversation_from_payload(payload)
    rescue => e
      Rails.logger.error "[SOCIALWISE] Error extracting conversation from payload: #{e.class}: #{e.message}"
      nil
    end

    # Extract contact object from payload with error handling
    def safe_extract_contact_from_payload(payload)
      extract_contact_from_payload(payload)
    rescue => e
      Rails.logger.error "[SOCIALWISE] Error extracting contact from payload: #{e.class}: #{e.message}"
      nil
    end

    # Extract inbox object from payload with error handling
    def safe_extract_inbox_from_payload(payload)
      extract_inbox_from_payload(payload)
    rescue => e
      Rails.logger.error "[SOCIALWISE] Error extracting inbox from payload: #{e.class}: #{e.message}"
      nil
    end

    # Original extraction methods (kept for backward compatibility)
    
    # Extract message object from payload
    def extract_message_from_payload(payload)
      payload[:message] || payload['message']
    end

    # Extract conversation object from payload
    def extract_conversation_from_payload(payload)
      payload[:conversation] || payload['conversation']
    end

    # Extract contact object from payload
    def extract_contact_from_payload(payload)
      payload[:contact] || payload['contact']
    end

    # Extract inbox object from payload
    def extract_inbox_from_payload(payload)
      payload[:inbox] || payload['inbox']
    end

    # Extract WhatsApp API key from inbox channel
    def extract_whatsapp_api_key(inbox)
      return nil unless inbox&.channel_type == 'Channel::Whatsapp'
      
      begin
        api_key = inbox.channel.provider_config&.dig('api_key')
        Rails.logger.info "[SOCIALWISE] WhatsApp API key extracted: #{api_key.present? ? 'Present' : 'Not found'}"
        api_key
      rescue => e
        Rails.logger.error "[SOCIALWISE] Error extracting WhatsApp API key: #{e.class}: #{e.message}"
        nil
      end
    end

    # Build WhatsApp identifiers section
    def build_whatsapp_identifiers(message, contact)
      unless message && contact
        Rails.logger.debug "[SOCIALWISE] Missing message or contact for WhatsApp identifiers"
        return {
          'wamid' => nil,
          'whatsapp_id' => nil,
          'contact_source' => nil
        }
      end

      source_id = message.source_id
      contact_source = contact.contact_inboxes&.first&.source_id
      
      {
        'wamid' => source_id,
        'whatsapp_id' => source_id,
        'contact_source' => contact_source
      }
    rescue => e
      Rails.logger.error "[SOCIALWISE] Error building WhatsApp identifiers: #{e.class}: #{e.message}"
      Rails.logger.error "[SOCIALWISE] Message ID: #{message&.id}, Contact ID: #{contact&.id}"
      {
        'wamid' => nil,
        'whatsapp_id' => nil,
        'contact_source' => nil
      }
    end

    # Build contact data section
    def build_contact_data(contact)
      unless contact
        Rails.logger.debug "[SOCIALWISE] No contact provided for contact data"
        return {
          'id' => nil,
          'name' => nil,
          'phone_number' => nil,
          'email' => nil,
          'identifier' => nil,
          'custom_attributes' => {}
        }
      end

      {
        'id' => contact.id,
        'name' => contact.name,
        'phone_number' => contact.phone_number,
        'email' => contact.email,
        'identifier' => contact.identifier,
        'custom_attributes' => contact.custom_attributes || {}
      }
    rescue => e
      Rails.logger.error "[SOCIALWISE] Error building contact data: #{e.class}: #{e.message}"
      Rails.logger.error "[SOCIALWISE] Contact ID: #{contact&.id}, Contact class: #{contact&.class}"
      {
        'id' => contact&.id,
        'name' => nil,
        'phone_number' => nil,
        'email' => nil,
        'identifier' => nil,
        'custom_attributes' => {}
      }
    end

    # Build conversation data section
    def build_conversation_data(conversation)
      unless conversation
        Rails.logger.debug "[SOCIALWISE] No conversation provided for conversation data"
        return {
          'id' => nil,
          'status' => nil,
          'assignee_id' => nil,
          'created_at' => nil,
          'updated_at' => nil
        }
      end

      {
        'id' => conversation.id,
        'status' => conversation.status,
        'assignee_id' => conversation.assignee_id,
        'created_at' => conversation.created_at&.iso8601,
        'updated_at' => conversation.updated_at&.iso8601
      }
    rescue => e
      Rails.logger.error "[SOCIALWISE] Error building conversation data: #{e.class}: #{e.message}"
      Rails.logger.error "[SOCIALWISE] Conversation ID: #{conversation&.id}, Conversation class: #{conversation&.class}"
      {
        'id' => conversation&.id,
        'status' => nil,
        'assignee_id' => nil,
        'created_at' => nil,
        'updated_at' => nil
      }
    end

    # Build message data section
    def build_message_data(message)
      unless message
        Rails.logger.debug "[SOCIALWISE] No message provided for message data"
        return {
          'id' => nil,
          'content' => nil,
          'content_type' => nil,
          'message_type' => nil,
          'created_at' => nil
        }
      end

      {
        'id' => message.id,
        'content' => message.content,
        'content_type' => message.content_type,
        'message_type' => message.message_type,
        'created_at' => message.created_at&.iso8601
      }
    rescue => e
      Rails.logger.error "[SOCIALWISE] Error building message data: #{e.class}: #{e.message}"
      Rails.logger.error "[SOCIALWISE] Message ID: #{message&.id}, Message class: #{message&.class}"
      {
        'id' => message&.id,
        'content' => nil,
        'content_type' => nil,
        'message_type' => nil,
        'created_at' => nil
      }
    end

    # Build inbox data section
    def build_inbox_data(inbox)
      unless inbox
        Rails.logger.debug "[SOCIALWISE] No inbox provided for inbox data"
        return {
          'id' => nil,
          'name' => nil,
          'channel_type' => nil
        }
      end

      {
        'id' => inbox.id,
        'name' => inbox.name,
        'channel_type' => inbox.channel_type
      }
    rescue => e
      Rails.logger.error "[SOCIALWISE] Error building inbox data: #{e.class}: #{e.message}"
      Rails.logger.error "[SOCIALWISE] Inbox ID: #{inbox&.id}, Inbox class: #{inbox&.class}"
      {
        'id' => inbox&.id,
        'name' => nil,
        'channel_type' => nil
      }
    end

    # Build account data section
    def build_account_data(account)
      unless account
        Rails.logger.debug "[SOCIALWISE] No account provided for account data"
        return {
          'id' => nil,
          'name' => nil
        }
      end

      {
        'id' => account.id,
        'name' => account.name
      }
    rescue => e
      Rails.logger.error "[SOCIALWISE] Error building account data: #{e.class}: #{e.message}"
      Rails.logger.error "[SOCIALWISE] Account ID: #{account&.id}, Account class: #{account&.class}"
      {
        'id' => account&.id,
        'name' => nil
      }
    end

    # Build metadata section
    def build_metadata(inbox)
      is_whatsapp_channel = inbox&.channel_type == 'Channel::Whatsapp' ||
                           inbox&.channel&.class&.name == 'Channel::Whatsapp'

      {
        'socialwise_active' => true,
        'is_whatsapp_channel' => is_whatsapp_channel,
        'payload_version' => '2.0',
        'timestamp' => Time.current.iso8601,
        'has_whatsapp_api_key' => extract_whatsapp_api_key(inbox).present?
      }
    rescue => e
      Rails.logger.error "[SOCIALWISE] Error building metadata: #{e.message}"
      {
        'socialwise_active' => true,
        'payload_version' => '2.0',
        'timestamp' => Time.current.iso8601
      }
    end

    # Builds a comprehensive fallback data structure when full data collection fails
    # This ensures webhook delivery is never blocked by SocialWise failures
    # @param error [Exception] The error that caused the fallback
    # @param account [Account] The account (may be nil)
    # @return [Hash] Fallback socialwise-chatwit data structure
    def build_fallback_data_structure(error, account)
      Rails.logger.warn "[SOCIALWISE] Using fallback data structure due to error: #{error.class}: #{error.message}"
      
      # Build minimal but complete data structure
      fallback_data = {
        'whatsapp_identifiers' => {
          'wamid' => nil,
          'whatsapp_id' => nil,
          'contact_source' => nil
        },
        'contact_data' => {
          'id' => nil,
          'name' => nil,
          'phone_number' => nil,
          'email' => nil,
          'identifier' => nil,
          'custom_attributes' => {}
        },
        'conversation_data' => {
          'id' => nil,
          'status' => nil,
          'assignee_id' => nil,
          'created_at' => nil,
          'updated_at' => nil
        },
        'message_data' => {
          'id' => nil,
          'content' => nil,
          'content_type' => nil,
          'message_type' => nil,
          'created_at' => nil
        },
        'inbox_data' => {
          'id' => nil,
          'name' => nil,
          'channel_type' => nil
        },
        'account_data' => {
          'id' => account&.id,
          'name' => account&.name
        },
        'metadata' => {
          'socialwise_active' => true,
          'is_whatsapp_channel' => false,
          'payload_version' => '2.0',
          'timestamp' => Time.current.iso8601,
          'error' => "Data collection failed: #{error.class}: #{error.message}",
          'fallback_used' => true,
          'has_whatsapp_api_key' => false
        },
        'whatsapp_api_key' => nil
      }

      Rails.logger.info "[SOCIALWISE] Fallback data structure created successfully"
      fallback_data
    end
  end
end