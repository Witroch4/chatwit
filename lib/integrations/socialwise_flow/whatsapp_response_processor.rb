# frozen_string_literal: true

class Integrations::SocialwiseFlow::WhatsappResponseProcessor
  class << self
    # Main entry point for processing WhatsApp responses from SocialWise Flow
    # @param whatsapp_data [Hash] The WhatsApp response data from SocialWise Flow
    # @param message [Message] The message object from the conversation
    # @return [Boolean] true if processing was successful, false otherwise
    def process(whatsapp_data, message)
      start_time = Time.current
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] === STARTING WHATSAPP RESPONSE PROCESSING ==="
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Processing started at: #{start_time.iso8601}"
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Message ID: #{message.id}, Conversation ID: #{message.conversation.id}"
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Account ID: #{message.conversation.account_id}, Inbox ID: #{message.conversation.inbox_id}"
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Contact ID: #{message.conversation.contact_id}, Channel: #{message.conversation.inbox.channel_type}"
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] WhatsApp data: #{whatsapp_data.inspect}"

      # Validate that we have the required data
      unless whatsapp_data.is_a?(Hash)
        Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Invalid whatsapp_data: expected Hash, got #{whatsapp_data.class}"
        return fallback_to_text_message(message, whatsapp_data)
      end

      # Validate WhatsApp channel
      conversation = message.conversation
      unless conversation.inbox.channel_type == 'Channel::Whatsapp'
        Rails.logger.warn "[SOCIALWISE-FLOW-WHATSAPP] Rich messages only supported for WhatsApp channels, got: #{conversation.inbox.channel_type}"
        return fallback_to_text_message(message, whatsapp_data)
      end

      # Determine message type
      message_type = whatsapp_data['type']
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Message type: #{message_type}"

      # Route message based on type
      success = route_message(message_type, whatsapp_data, message)

      end_time = Time.current
      processing_duration = ((end_time - start_time) * 1000).round(2)
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] === WHATSAPP RESPONSE PROCESSING COMPLETED ==="
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Processing completed at: #{end_time.iso8601}"
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Total processing time: #{processing_duration}ms"
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] SUCCESS: Message type '#{message_type}' processed successfully"
      success
    rescue => e
      end_time = Time.current
      processing_duration = ((end_time - start_time) * 1000).round(2)
      Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Processing failed: #{e.class}: #{e.message}"
      Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Processing failed at: #{end_time.iso8601}"
      Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Processing time before failure: #{processing_duration}ms"
      Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Full context - Message ID: #{message.id}, Account ID: #{message.conversation.account_id}"
      Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Backtrace: #{e.backtrace.join('\n')}"
      fallback_to_text_message(message, whatsapp_data)
      false
    end

    private

    # Routes message to appropriate handler based on message type
    # @param message_type [String] The message type (interactive, text)
    # @param whatsapp_data [Hash] The WhatsApp payload
    # @param message [Message] The message object
    def route_message(message_type, whatsapp_data, message)
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Routing message with type: #{message_type}"

      case message_type
      when 'interactive'
        Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Processing Interactive Message"
        send_interactive_message(whatsapp_data, message)
      when 'text'
        Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Processing Text Message"
        send_text_message(whatsapp_data, message)
      else
        Rails.logger.warn "[SOCIALWISE-FLOW-WHATSAPP] Unknown message type: #{message_type}"
        # For unknown types, try to process as interactive if interactive payload exists
        if whatsapp_data['interactive'].present?
          Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Unknown type but interactive payload found, processing as interactive"
          send_interactive_message(whatsapp_data, message)
        else
          Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] No interactive payload, falling back to text message"
          fallback_to_text_message(message, whatsapp_data)
        end
      end
    end

    # Send Interactive Message using WhatsApp Rich Message Service
    # @param whatsapp_data [Hash] The WhatsApp payload
    # @param message [Message] The message object
    def send_interactive_message(whatsapp_data, message)
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] === STARTING INTERACTIVE MESSAGE SEND ==="
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Interactive payload: #{whatsapp_data['interactive'].inspect}"
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Message ID: #{message.id}, Conversation ID: #{message.conversation.id}"

      begin
        conversation = message.conversation
        interactive_payload = whatsapp_data['interactive']
        
        unless interactive_payload.present?
          Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Missing interactive payload"
          return fallback_to_text_message(message, whatsapp_data)
        end

        # Extract text content for dashboard display
        text_content = extract_text_content(whatsapp_data)
        Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Extracted text content: #{text_content}"

        # Create message for dashboard display (Requirement 7.1, 7.2)
        outgoing_message = nil
        begin
          # Para mensagens interativas, usar content_type 'integrations' com payload completo
          # O WhatsApp service pode usar send_interactive_payload para payloads prontos
          outgoing_message = conversation.messages.create!(
            message_type: :outgoing,
            content: text_content,
            content_type: 'integrations',
            content_attributes: {
              'interactive' => interactive_payload,
              'type' => whatsapp_data['type'],
              'whatsapp_interactive_payload' => interactive_payload
            },
            account_id: conversation.account_id,
            inbox_id: conversation.inbox_id,
            additional_attributes: { skip_send_reply: true }
          )
          Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Interactive message created: #{outgoing_message.id}"
          
        rescue StandardError => message_creation_error
          # Requirement 6.2: Continue processing even if message creation fails
          Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Message creation failed: #{message_creation_error.class}: #{message_creation_error.message}"
          Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Text content: #{text_content}"
          Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Backtrace: #{message_creation_error.backtrace.first(3).join('\n')}"
          
          # Try to create a simple fallback message
          begin
            outgoing_message = conversation.messages.create!(
              message_type: :outgoing,
              content: text_content || "WhatsApp message",
              content_type: 'text',
              account_id: conversation.account_id,
              inbox_id: conversation.inbox_id,
              additional_attributes: { skip_send_reply: true }
            )
            Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Fallback message created: #{outgoing_message.id}"
          rescue StandardError => fallback_error
            Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Fallback message creation also failed: #{fallback_error.class}: #{fallback_error.message}"
            return false # Can't create message, abort processing
          end
        end

        # Send message using native WhatsApp service
        if outgoing_message
          begin
            # Para mensagens interativas, usar o método send_interactive_payload diretamente
            contact_source_id = conversation.contact.get_source_id(conversation.inbox.id)
            channel = conversation.inbox.channel
            
            Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Sending interactive message via send_interactive_payload"
            Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Contact source ID: #{contact_source_id}"
            
            message_id = channel.provider_service.send_interactive_payload(contact_source_id, outgoing_message, interactive_payload)
            
            if message_id.present?
              outgoing_message.update!(source_id: message_id)
              Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Interactive message sent successfully, source_id: #{message_id}"
            else
              Rails.logger.warn "[SOCIALWISE-FLOW-WHATSAPP] Interactive message sent but no message_id returned"
            end
            
          rescue StandardError => sending_error
            # Requirement 6.2: Log rich message sending failures but continue processing
            Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Message sending failed: #{sending_error.class}: #{sending_error.message}"
            Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Message ID: #{outgoing_message.id}"
            Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Contact source ID: #{conversation.contact.get_source_id(conversation.inbox.id) rescue 'unknown'}"
            Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Backtrace: #{sending_error.backtrace.first(5).join('\n')}"
            # Message is created in dashboard, sending failure doesn't affect that
          end
        end

        Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] === INTERACTIVE MESSAGE SEND COMPLETED ==="
        true
      rescue => e
        Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Interactive message send failed: #{e.class}: #{e.message}"
        Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Backtrace: #{e.backtrace.join('\n')}"
        Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Falling back to text message due to error"
        
        fallback_to_text_message(message, whatsapp_data)
        false
      end
    end

    # Send Text Message
    # @param whatsapp_data [Hash] The WhatsApp payload
    # @param message [Message] The message object
    def send_text_message(whatsapp_data, message)
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] === STARTING TEXT MESSAGE SEND ==="
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Text payload: #{whatsapp_data.inspect}"

      begin
        conversation = message.conversation
        text_content = extract_text_content(whatsapp_data)
        Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Extracted text content: #{text_content}"
        
        # Create message for dashboard display (Requirement 7.1, 7.2)
        outgoing_message = nil
        begin
          # Para mensagens de texto simples
          outgoing_message = conversation.messages.create!(
            message_type: :outgoing,
            content: text_content,
            content_type: 'text',
            account_id: conversation.account_id,
            inbox_id: conversation.inbox_id,
            additional_attributes: { skip_send_reply: true }
          )
          Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Text message created: #{outgoing_message.id}"
          
        rescue StandardError => message_creation_error
          # Requirement 6.2: Continue processing even if message creation fails
          Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Message creation failed: #{message_creation_error.class}: #{message_creation_error.message}"
          Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Text content: #{text_content}"
          Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Backtrace: #{message_creation_error.backtrace.first(3).join('\n')}"
          
          # Try to create a simple fallback message
          begin
            outgoing_message = conversation.messages.create!(
              message_type: :outgoing,
              content: text_content || "WhatsApp message",
              content_type: 'text',
              account_id: conversation.account_id,
              inbox_id: conversation.inbox_id,
              additional_attributes: { skip_send_reply: true }
            )
            Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Fallback message created: #{outgoing_message.id}"
          rescue StandardError => fallback_error
            Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Fallback message creation also failed: #{fallback_error.class}: #{fallback_error.message}"
            return false # Can't create message, abort processing
          end
        end

        # Send message using native WhatsApp service
        if outgoing_message
          begin
            # Para mensagens de texto, usar o serviço padrão
            Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Sending text message via SendOnWhatsappService"
            Whatsapp::SendOnWhatsappService.new(message: outgoing_message).perform
            Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Text message sent successfully"
            
          rescue StandardError => sending_error
            # Requirement 6.2: Log rich message sending failures but continue processing
            Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Message sending failed: #{sending_error.class}: #{sending_error.message}"
            Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Message ID: #{outgoing_message.id}"
            Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Contact source ID: #{conversation.contact.get_source_id(conversation.inbox.id) rescue 'unknown'}"
            Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Backtrace: #{sending_error.backtrace.first(5).join('\n')}"
            # Message is created in dashboard, sending failure doesn't affect that
          end
        end

        Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] === TEXT MESSAGE SEND COMPLETED ==="
        true
      rescue => e
        Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Text message send failed: #{e.class}: #{e.message}"
        Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Backtrace: #{e.backtrace.join('\n')}"
        false
      end
    end



    # Extract text content from WhatsApp payload
    # @param whatsapp_data [Hash] The WhatsApp payload
    # @return [String] Extracted text content
    def extract_text_content(whatsapp_data)
      # Try different locations for text content
      whatsapp_data.dig('interactive', 'body', 'text') ||
      whatsapp_data.dig('text', 'body') ||
      whatsapp_data['text'] ||
      'WhatsApp message'
    end

    # Fallback to text message when rich message processing fails
    # @param message [Message] The original message
    # @param whatsapp_data [Hash] The WhatsApp data for text extraction
    # @return [Boolean] true if fallback was successful
    def fallback_to_text_message(message, whatsapp_data)
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Falling back to text message"

      begin
        fallback_text = extract_text_content(whatsapp_data)
        
        conversation = message.conversation
        fallback_message = conversation.messages.create!(
          content: fallback_text,
          message_type: :outgoing,
          account_id: conversation.account_id,
          inbox_id: conversation.inbox_id
        )

        Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Fallback text message created successfully: #{fallback_text}"
        Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Fallback message ID: #{fallback_message.id}"
        true
      rescue => e
        Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Fallback to text message failed: #{e.class}: #{e.message}"
        Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Fallback backtrace: #{e.backtrace.join('\n')}"
        false
      end
    end


  end
end