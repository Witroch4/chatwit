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
        fallback_to_text_message(message, whatsapp_data)
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
        interactive_payload = whatsapp_data['interactive']
        
        unless interactive_payload.present?
          Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Missing interactive payload"
          return fallback_to_text_message(message, whatsapp_data)
        end

        # Create outgoing message DIRECTLY as rich content - EXACT INSTAGRAM PATTERN
        Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Creating outgoing message DIRECTLY as rich content (exact Instagram pattern)"
        conversation = message.conversation
        outgoing_message = create_rich_outgoing_message(conversation, interactive_payload, whatsapp_data)
        Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Created outgoing message ID: #{outgoing_message.id} with skip_send_reply flag"

        # Send using WhatsApp Rich Message Service - EXACT INSTAGRAM PATTERN
        Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Creating WhatsApp Rich Message Service with payload: #{interactive_payload.inspect}"
        rich_message_service = Whatsapp::RichMessageService.new(
          message: outgoing_message, 
          interactive_payload: interactive_payload
        )
        Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Created WhatsApp Rich Message Service successfully"

        # Perform the send operation
        send_start_time = Time.current
        Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] About to call rich_message_service.perform"
        message_id = rich_message_service.perform
        send_end_time = Time.current
        Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] rich_message_service.perform completed successfully"
        
        if message_id.present?
          # Use update_columns to avoid triggering callbacks and WebSocket updates (prevents flash effect)
          outgoing_message.update_columns(source_id: message_id, updated_at: Time.current)
          Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Interactive message sent successfully, source_id: #{message_id}"
        else
          Rails.logger.warn "[SOCIALWISE-FLOW-WHATSAPP] Interactive message sent but no message_id returned"
        end
        
        # Log performance metrics for the send operation
        log_performance_metrics(
          "Interactive Message Send",
          send_start_time,
          send_end_time,
          message,
          {
            interactive_type: interactive_payload['type'],
            buttons_count: interactive_payload.dig('action', 'buttons')&.length || 0,
            sections_count: interactive_payload.dig('action', 'sections')&.length || 0
          }
        )

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
        
        # Create simple text message
        outgoing_message = conversation.messages.create!(
          content: text_content,
          message_type: :outgoing,
          account_id: conversation.account_id,
          inbox_id: conversation.inbox_id
        )

        Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Text message created: #{outgoing_message.id}"
        Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] === TEXT MESSAGE SEND COMPLETED ==="
        true
      rescue => e
        Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Text message send failed: #{e.class}: #{e.message}"
        Rails.logger.error "[SOCIALWISE-FLOW-WHATSAPP] Backtrace: #{e.backtrace.join('\n')}"
        false
      end
    end

    # Create outgoing message with rich content directly to avoid flash effect - INSTAGRAM PATTERN
    # @param conversation [Conversation] The conversation to create the message in
    # @param interactive_payload [Hash] The WhatsApp interactive payload
    # @param original_payload [Hash] The original SocialWise Flow payload
    # @return [Message] The created message
    def create_rich_outgoing_message(conversation, interactive_payload, original_payload)
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Creating rich outgoing message (Instagram pattern)"
      
      # ALWAYS create message directly as rich content - NO FEATURE FLAG DEPENDENCY
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Creating rich message directly (feature flag dependency removed)"
      
      # Create message directly as rich content to avoid flash effect - EXACT INSTAGRAM PATTERN
      create_rich_message_directly(conversation, interactive_payload, original_payload)
    end

    # Create message directly as rich content - EXACT INSTAGRAM PATTERN
    # @param conversation [Conversation] The conversation to create the message in
    # @param interactive_payload [Hash] The WhatsApp interactive payload
    # @param original_payload [Hash] The original SocialWise Flow payload
    # @return [Message] The created message
    def create_rich_message_directly(conversation, interactive_payload, original_payload)
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Creating message directly as rich content (EXACT Instagram pattern)"
      
      # Use the WhatsApp Renderer Mapper to convert payload to Chatwoot format - EXACT INSTAGRAM PATTERN
      mapped_result = Messages::WhatsappRendererMapper.map(interactive_payload)
      
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Mapped content_type: #{mapped_result.content_type}"
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Mapped fallback_text: #{mapped_result.fallback_text}"
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Mapped content_attributes keys: #{mapped_result.content_attributes.keys}"

      # Create message directly with rich content - EXACT INSTAGRAM PATTERN
      message = conversation.messages.create!(
        content: mapped_result.fallback_text,
        content_type: mapped_result.content_type,
        content_attributes: mapped_result.content_attributes,
        message_type: :outgoing,
        account_id: conversation.account_id,
        inbox_id: conversation.inbox_id,
        additional_attributes: { skip_send_reply: true }
      )

      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Created rich message directly with ID: #{message.id}"
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Message content_type: #{message.content_type}"
      
      message
    end

    # Create regular text message (existing behavior)
    # @param conversation [Conversation] The conversation to create the message in
    # @param original_payload [Hash] The original SocialWise Flow payload
    # @return [Message] The created message
    def create_text_message(conversation, original_payload)
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Creating regular text message"
      
      conversation.messages.create!(
        content: extract_text_content(original_payload),
        message_type: :outgoing,
        account_id: conversation.account_id,
        inbox_id: conversation.inbox_id,
        additional_attributes: { skip_send_reply: true }
      )
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

    # Logs performance metrics for monitoring and optimization
    # @param operation [String] The operation being measured
    # @param start_time [Time] The start time of the operation
    # @param end_time [Time] The end time of the operation
    # @param message [Message] The message object for context
    # @param additional_data [Hash] Additional data to log
    def log_performance_metrics(operation, start_time, end_time, message, additional_data = {})
      duration_ms = ((end_time - start_time) * 1000).round(2)
      
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] === PERFORMANCE METRICS ==="
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Operation: #{operation}"
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Duration: #{duration_ms}ms"
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Start time: #{start_time.iso8601}"
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] End time: #{end_time.iso8601}"
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Message ID: #{message.id}"
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Conversation ID: #{message.conversation.id}"
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] Account ID: #{message.conversation.account_id}"
      
      # Log additional performance data
      additional_data.each do |key, value|
        Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] #{key.to_s.humanize}: #{value}"
      end
      
      # Performance warnings
      if duration_ms > 5000
        Rails.logger.warn "[SOCIALWISE-FLOW-WHATSAPP] PERFORMANCE WARNING: #{operation} took #{duration_ms}ms (>5s)"
      elsif duration_ms > 2000
        Rails.logger.warn "[SOCIALWISE-FLOW-WHATSAPP] PERFORMANCE NOTICE: #{operation} took #{duration_ms}ms (>2s)"
      end
      
      Rails.logger.info "[SOCIALWISE-FLOW-WHATSAPP] === END PERFORMANCE METRICS ==="
    end
  end
end