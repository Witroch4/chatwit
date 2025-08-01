# frozen_string_literal: true

class Integrations::Socialwise::InstagramResponseProcessor
  class << self
    # Main entry point for processing socialwiseResponse payloads
    # @param socialwise_data [Hash] The socialwiseResponse data from Dialogflow
    # @param message [Message] The message object from the conversation
    # @return [Boolean] true if processing was successful, false otherwise
    def process(socialwise_data, message)
      start_time = Time.current
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] === STARTING SOCIALWISE RESPONSE PROCESSING ==="
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Processing started at: #{start_time.iso8601}"
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Message ID: #{message.id}, Conversation ID: #{message.conversation.id}"
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Account ID: #{message.conversation.account_id}, Inbox ID: #{message.conversation.inbox_id}"
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Contact ID: #{message.conversation.contact_id}, Channel: #{message.conversation.inbox.channel_type}"
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] SocialWise data: #{socialwise_data.inspect}"

      # Validate that we have the required data
      unless socialwise_data.is_a?(Hash)
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Invalid socialwise_data: expected Hash, got #{socialwise_data.class}"
        return fallback_to_text_message(message, socialwise_data)
      end

      message_format = socialwise_data['message_format']
      payload = socialwise_data['payload']

      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Message format: #{message_format}"
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Payload: #{payload.inspect}"

      # Validate payload structure
      unless validate_payload(message_format, payload)
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Invalid payload for format: #{message_format}"
        return fallback_to_text_message(message, socialwise_data)
      end

      # Route message based on format
      route_message(message_format, payload, message)

      end_time = Time.current
      processing_duration = ((end_time - start_time) * 1000).round(2)
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] === SOCIALWISE RESPONSE PROCESSING COMPLETED ==="
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Processing completed at: #{end_time.iso8601}"
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Total processing time: #{processing_duration}ms"
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] SUCCESS: Message format '#{message_format}' processed successfully"
      true
    rescue => e
      end_time = Time.current
      processing_duration = ((end_time - start_time) * 1000).round(2)
      Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Processing failed: #{e.class}: #{e.message}"
      Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Processing failed at: #{end_time.iso8601}"
      Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Processing time before failure: #{processing_duration}ms"
      Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Full context - Message ID: #{message.id}, Account ID: #{message.conversation.account_id}"
      Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Backtrace: #{e.backtrace.join('\n')}"
      fallback_to_text_message(message, socialwise_data)
      false
    end

    private

    # Routes message to appropriate handler based on message_format
    # @param message_format [String] The format type (GENERIC_TEMPLATE, BUTTON_TEMPLATE, QUICK_REPLIES)
    # @param payload [Hash] The message payload
    # @param message [Message] The message object
    def route_message(message_format, payload, message)
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Routing message with format: #{message_format}"

      # Validate Instagram channel
      conversation = message.conversation
      unless conversation.inbox.channel_type == 'Channel::Instagram'
        Rails.logger.warn "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Rich messages only supported for Instagram channels, got: #{conversation.inbox.channel_type}"
        return fallback_to_text_message(message, { 'payload' => payload })
      end

      case message_format
      when 'GENERIC_TEMPLATE'
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Processing Generic Template"
        send_generic_template(payload, message)
      when 'BUTTON_TEMPLATE'
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Processing Button Template"
        send_button_template(payload, message)
      when 'QUICK_REPLIES'
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Processing Quick Replies"
        send_quick_replies(payload, message)
      else
        Rails.logger.warn "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Unknown message format: #{message_format}"
        log_unknown_format(message_format)
        fallback_to_text_message(message, { 'payload' => payload })
      end
    end

    # Validates payload structure for each message format
    # @param message_format [String] The format type
    # @param payload [Hash] The payload to validate
    # @return [Boolean] true if valid, false otherwise
    def validate_payload(message_format, payload)
      validation_start_time = Time.current
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] === STARTING PAYLOAD VALIDATION ==="
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Validating payload for format: #{message_format}"
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Payload size: #{payload.inspect.length} characters"

      unless payload.is_a?(Hash)
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] VALIDATION FAILED: Payload is not a Hash, got #{payload.class}"
        return false
      end

      validation_result = case message_format
      when 'GENERIC_TEMPLATE'
        validate_generic_template(payload)
      when 'BUTTON_TEMPLATE'
        validate_button_template(payload)
      when 'QUICK_REPLIES'
        validate_quick_replies(payload)
      else
        Rails.logger.warn "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Unknown format for validation: #{message_format}"
        Rails.logger.warn "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Supported formats: GENERIC_TEMPLATE, BUTTON_TEMPLATE, QUICK_REPLIES"
        false
      end

      validation_end_time = Time.current
      validation_duration = ((validation_end_time - validation_start_time) * 1000).round(2)
      
      if validation_result
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] === PAYLOAD VALIDATION SUCCESSFUL ==="
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Validation time: #{validation_duration}ms"
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Format: #{message_format} validated successfully"
      else
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] === PAYLOAD VALIDATION FAILED ==="
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Validation time: #{validation_duration}ms"
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Format: #{message_format} validation failed"
      end
      
      validation_result
    end

    # Validates Generic Template payload structure
    # @param payload [Hash] The payload to validate
    # @return [Boolean] true if valid, false otherwise
    def validate_generic_template(payload)
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Validating Generic Template payload"

      # Check required fields
      unless payload['template_type'] == 'generic'
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Invalid template_type: expected 'generic', got '#{payload['template_type']}'"
        return false
      end

      unless payload['elements'].is_a?(Array) && payload['elements'].any?
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Invalid elements: must be non-empty array"
        return false
      end

      # Instagram API constraint: max 10 elements in carousel
      if payload['elements'].length > 10
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Too many elements: max 10 allowed, got #{payload['elements'].length}"
        return false
      end

      # Validate each element
      payload['elements'].each_with_index do |element, index|
        unless element.is_a?(Hash)
          Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Element #{index} is not a hash"
          return false
        end

        unless element['title'].present?
          Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Element #{index} missing required title"
          return false
        end

        # Validate title length (Instagram limit: 80 characters)
        if element['title'].length > 80
          Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Element #{index} title too long: max 80 characters, got #{element['title'].length}"
          return false
        end

        # Validate subtitle length if present (Instagram limit: 80 characters)
        if element['subtitle'].present? && element['subtitle'].length > 80
          Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Element #{index} subtitle too long: max 80 characters, got #{element['subtitle'].length}"
          return false
        end

        # Validate image URL format if present
        if element['image_url'].present?
          unless validate_image_url(element['image_url'], "Element #{index} image_url")
            return false
          end
        end

        # Validate buttons if present
        if element['buttons'].present?
          unless element['buttons'].is_a?(Array) && element['buttons'].length <= 3
            Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Element #{index} has invalid buttons (max 3 allowed)"
            return false
          end

          element['buttons'].each_with_index do |button, btn_index|
            unless validate_button(button, "Element #{index} Button #{btn_index}")
              return false
            end
          end
        end
      end

      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Generic Template payload validation passed"
      true
    end

    # Validates Button Template payload structure
    # @param payload [Hash] The payload to validate
    # @return [Boolean] true if valid, false otherwise
    def validate_button_template(payload)
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Validating Button Template payload"

      # Check required fields
      unless payload['template_type'] == 'button'
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Invalid template_type: expected 'button', got '#{payload['template_type']}'"
        return false
      end

      unless payload['text'].present?
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Button Template missing required text"
        return false
      end

      # Validate text length (Instagram limit: 2000 characters)
      if payload['text'].length > 2000
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Button Template text too long: max 2000 characters, got #{payload['text'].length}"
        return false
      end

      unless payload['buttons'].is_a?(Array) && payload['buttons'].any? && payload['buttons'].length <= 3
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Invalid buttons: must be array with 1-3 buttons"
        return false
      end

      # Validate each button
      payload['buttons'].each_with_index do |button, index|
        unless validate_button(button, "Button #{index}")
          return false
        end
      end

      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Button Template payload validation passed"
      true
    end

    # Validates Quick Replies payload structure
    # @param payload [Hash] The payload to validate
    # @return [Boolean] true if valid, false otherwise
    def validate_quick_replies(payload)
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Validating Quick Replies payload"

      # Check required fields
      unless payload['text'].present?
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Quick Replies missing required text"
        return false
      end

      # Validate text length (Instagram limit: 2000 characters)
      if payload['text'].length > 2000
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Quick Replies text too long: max 2000 characters, got #{payload['text'].length}"
        return false
      end

      unless payload['quick_replies'].is_a?(Array) && payload['quick_replies'].any? && payload['quick_replies'].length <= 13
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Invalid quick_replies: must be array with 1-13 quick replies"
        return false
      end

      # Validate each quick reply
      payload['quick_replies'].each_with_index do |quick_reply, index|
        unless quick_reply.is_a?(Hash)
          Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Quick reply #{index} is not a hash"
          return false
        end

        unless quick_reply['content_type'] == 'text'
          Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Quick reply #{index} invalid content_type: expected 'text', got '#{quick_reply['content_type']}'"
          return false
        end

        unless quick_reply['title'].present?
          Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Quick reply #{index} missing required title"
          return false
        end

        # Validate title length (Instagram limit: 20 characters for quick reply titles)
        if quick_reply['title'].length > 20
          Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Quick reply #{index} title too long: max 20 characters, got #{quick_reply['title'].length}"
          return false
        end

        unless quick_reply['payload'].present?
          Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Quick reply #{index} missing required payload"
          return false
        end

        # Validate payload length (Instagram limit: 1000 characters)
        if quick_reply['payload'].length > 1000
          Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Quick reply #{index} payload too long: max 1000 characters, got #{quick_reply['payload'].length}"
          return false
        end
      end

      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Quick Replies payload validation passed"
      true
    end

    # Validates individual button structure
    # @param button [Hash] The button to validate
    # @param context [String] Context for error messages
    # @return [Boolean] true if valid, false otherwise
    def validate_button(button, context)
      unless button.is_a?(Hash)
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] #{context} is not a hash"
        return false
      end

      unless button['type'].present?
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] #{context} missing required type"
        return false
      end

      unless button['title'].present?
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] #{context} missing required title"
        return false
      end

      # Validate title length (Instagram limit: 20 characters for button titles)
      if button['title'].length > 20
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] #{context} title too long: max 20 characters, got #{button['title'].length}"
        return false
      end

      case button['type']
      when 'postback'
        unless button['payload'].present?
          Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] #{context} postback button missing required payload"
          return false
        end
        
        # Validate payload length (Instagram limit: 1000 characters)
        if button['payload'].length > 1000
          Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] #{context} postback payload too long: max 1000 characters, got #{button['payload'].length}"
          return false
        end
      when 'web_url'
        unless button['url'].present?
          Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] #{context} web_url button missing required url"
          return false
        end
        
        # Enhanced URL validation
        unless validate_web_url(button['url'], context)
          return false
        end
      else
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] #{context} has invalid type: #{button['type']} (must be 'postback' or 'web_url')"
        return false
      end

      true
    end

    # Validates web URL format and constraints
    # @param url [String] The URL to validate
    # @param context [String] Context for error messages
    # @return [Boolean] true if valid, false otherwise
    def validate_web_url(url, context)
      # Basic URL format validation
      unless url =~ URI::DEFAULT_PARSER.make_regexp(%w[http https])
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] #{context} has invalid URL format: #{url}"
        return false
      end

      # URL length validation (Instagram limit: 2000 characters)
      if url.length > 2000
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] #{context} URL too long: max 2000 characters, got #{url.length}"
        return false
      end

      # Parse URL to validate structure
      begin
        parsed_uri = URI.parse(url)
        
        # Ensure scheme is present and valid
        unless %w[http https].include?(parsed_uri.scheme)
          Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] #{context} URL must use http or https scheme: #{url}"
          return false
        end

        # Ensure host is present
        unless parsed_uri.host.present?
          Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] #{context} URL missing host: #{url}"
          return false
        end

        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] #{context} URL validation passed: #{url}"
        true
      rescue URI::InvalidURIError => e
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] #{context} invalid URL structure: #{e.message}"
        false
      end
    end

    # Validates image URL format and constraints
    # @param image_url [String] The image URL to validate
    # @param context [String] Context for error messages
    # @return [Boolean] true if valid, false otherwise
    def validate_image_url(image_url, context)
      # Basic URL validation first
      unless validate_web_url(image_url, context)
        return false
      end

      # Check for common image file extensions
      valid_extensions = %w[.jpg .jpeg .png .gif .webp]
      url_path = URI.parse(image_url).path.downcase
      
      unless valid_extensions.any? { |ext| url_path.end_with?(ext) }
        Rails.logger.warn "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] #{context} may not be a valid image URL (no recognized extension): #{image_url}"
        # Don't fail validation, just warn - some image URLs don't have extensions
      end

      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] #{context} image URL validation passed: #{image_url}"
      true
    end

    # Build Instagram API compatible Generic Template payload
    # @param payload [Hash] The original Generic Template payload
    # @return [Hash] Instagram API compatible payload
    def build_generic_template_payload(payload)
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Building Instagram Generic Template payload"
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Original payload: #{payload.inspect}"

      instagram_payload = {
        'template_type' => 'generic',
        'elements' => build_generic_template_elements(payload['elements'])
      }

      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Built Instagram payload: #{instagram_payload.inspect}"
      instagram_payload
    end

    # Build elements array for Generic Template
    # @param elements [Array] The original elements array
    # @return [Array] Instagram API compatible elements
    def build_generic_template_elements(elements)
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Building #{elements&.length} Generic Template elements"

      return [] unless elements.is_a?(Array)

      instagram_elements = elements.map.with_index do |element, index|
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Building element #{index}: #{element.inspect}"

        instagram_element = {
          'title' => element['title']
        }

        # Add optional fields
        instagram_element['subtitle'] = element['subtitle'] if element['subtitle'].present?
        instagram_element['image_url'] = element['image_url'] if element['image_url'].present?

        # Handle buttons if present
        if element['buttons'].present? && element['buttons'].is_a?(Array)
          Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Element #{index} has #{element['buttons'].length} buttons"
          instagram_element['buttons'] = build_generic_template_buttons(element['buttons'], index)
        end

        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Built element #{index}: #{instagram_element.inspect}"
        instagram_element
      end

      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Built #{instagram_elements.length} Instagram elements"
      instagram_elements
    end

    # Build buttons array for Generic Template elements
    # @param buttons [Array] The original buttons array
    # @param element_index [Integer] The element index for logging
    # @return [Array] Instagram API compatible buttons
    def build_generic_template_buttons(buttons, element_index)
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Building buttons for element #{element_index}"

      return [] unless buttons.is_a?(Array)

      instagram_buttons = buttons.map.with_index do |button, button_index|
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Building element #{element_index} button #{button_index}: #{button.inspect}"

        instagram_button = {
          'type' => button['type'],
          'title' => button['title']
        }

        # Handle button type specific fields
        case button['type']
        when 'postback'
          instagram_button['payload'] = button['payload']
          Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Added postback payload: #{button['payload']}"
        when 'web_url'
          instagram_button['url'] = button['url']
          Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Added web URL: #{button['url']}"
        end

        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Built element #{element_index} button #{button_index}: #{instagram_button.inspect}"
        instagram_button
      end

      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Built #{instagram_buttons.length} buttons for element #{element_index}"
      instagram_buttons
    end

    # Build Instagram API compatible Button Template payload
    # @param payload [Hash] The original Button Template payload
    # @return [Hash] Instagram API compatible payload
    def build_button_template_payload(payload)
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Building Instagram Button Template payload"
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Original payload: #{payload.inspect}"

      instagram_payload = {
        'template_type' => 'button',
        'text' => payload['text'],
        'buttons' => build_button_template_buttons(payload['buttons'])
      }

      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Built Instagram payload: #{instagram_payload.inspect}"
      instagram_payload
    end

    # Build buttons array for Button Template
    # @param buttons [Array] The original buttons array
    # @return [Array] Instagram API compatible buttons
    def build_button_template_buttons(buttons)
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Building Button Template buttons"

      return [] unless buttons.is_a?(Array)

      instagram_buttons = buttons.map.with_index do |button, button_index|
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Building Button Template button #{button_index}: #{button.inspect}"

        instagram_button = {
          'type' => button['type'],
          'title' => button['title']
        }

        # Handle button type specific fields
        case button['type']
        when 'postback'
          instagram_button['payload'] = button['payload']
          Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Added postback payload: #{button['payload']}"
        when 'web_url'
          instagram_button['url'] = button['url']
          Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Added web URL: #{button['url']}"
        end

        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Built Button Template button #{button_index}: #{instagram_button.inspect}"
        instagram_button
      end

      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Built #{instagram_buttons.length} buttons for Button Template"
      instagram_buttons
    end

    # Send Generic Template message using Instagram Rich Message Service
    # @param payload [Hash] The Generic Template payload
    # @param message [Message] The message object
    def send_generic_template(payload, message)
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] === STARTING GENERIC TEMPLATE SEND ==="
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Generic Template payload: #{payload.inspect}"
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Message ID: #{message.id}, Conversation ID: #{message.conversation.id}"

      begin
        # Build Instagram API compatible Generic Template structure
        instagram_payload = build_generic_template_payload(payload)
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Built Instagram payload: #{instagram_payload.inspect}"

        # Create outgoing message for rich message service
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Creating outgoing message for rich message service"
        conversation = message.conversation
        outgoing_message = conversation.messages.create!(
          content: extract_fallback_text({ 'payload' => payload }),
          message_type: :outgoing,
          account_id: conversation.account_id,
          inbox_id: conversation.inbox_id
        )
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Created outgoing message ID: #{outgoing_message.id}"

        # Send using Instagram Rich Message Service
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Creating Instagram Rich Message Service with payload: #{instagram_payload.inspect}"
        rich_message_service = Instagram::RichMessageService.new(message: outgoing_message, rich_payload: instagram_payload)
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Created Instagram Rich Message Service successfully"
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Service class: #{rich_message_service.class}"
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Service responds to perform: #{rich_message_service.respond_to?(:perform)}"

        # Perform the send operation
        send_start_time = Time.current
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] About to call rich_message_service.perform"
        rich_message_service.perform
        send_end_time = Time.current
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] rich_message_service.perform completed successfully"
        
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Generic Template sent successfully"
        
        # Log performance metrics for the send operation
        log_performance_metrics(
          "Generic Template Send",
          send_start_time,
          send_end_time,
          message,
          {
            elements_count: payload['elements']&.length || 0,
            total_buttons: payload['elements']&.sum { |e| e['buttons']&.length || 0 } || 0
          }
        )

        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] === GENERIC TEMPLATE SEND COMPLETED ==="
        true
      rescue => e
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Generic Template send failed: #{e.class}: #{e.message}"
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Backtrace: #{e.backtrace.join('\n')}"
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Falling back to text message due to error"
        
        fallback_to_text_message(message, { 'payload' => payload })
        false
      end
    end

    # Send Button Template message using Instagram Rich Message Service
    # @param payload [Hash] The Button Template payload
    # @param message [Message] The message object
    def send_button_template(payload, message)
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] === STARTING BUTTON TEMPLATE SEND ==="
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Button Template payload: #{payload.inspect}"
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Message ID: #{message.id}, Conversation ID: #{message.conversation.id}"

      begin
        # Build Instagram API compatible Button Template structure
        instagram_payload = build_button_template_payload(payload)
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Built Instagram payload: #{instagram_payload.inspect}"

        # Create outgoing message for rich message service
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Creating outgoing message for rich message service"
        conversation = message.conversation
        outgoing_message = conversation.messages.create!(
          content: extract_fallback_text({ 'payload' => payload }),
          message_type: :outgoing,
          account_id: conversation.account_id,
          inbox_id: conversation.inbox_id
        )
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Created outgoing message ID: #{outgoing_message.id}"

        # Send using Instagram Rich Message Service
        rich_message_service = Instagram::RichMessageService.new(message: outgoing_message, rich_payload: instagram_payload)
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Created Instagram Rich Message Service"

        # Perform the send operation
        send_start_time = Time.current
        rich_message_service.perform
        send_end_time = Time.current
        
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Button Template sent successfully"
        
        # Log performance metrics for the send operation
        log_performance_metrics(
          "Button Template Send",
          send_start_time,
          send_end_time,
          message,
          {
            buttons_count: payload['buttons']&.length || 0,
            text_length: payload['text']&.length || 0
          }
        )

        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] === BUTTON TEMPLATE SEND COMPLETED ==="
        true
      rescue => e
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Button Template send failed: #{e.class}: #{e.message}"
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Backtrace: #{e.backtrace.join('\n')}"
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Falling back to text message due to error"
        
        fallback_to_text_message(message, { 'payload' => payload })
        false
      end
    end

    # Build Instagram API compatible Quick Replies payload
    # @param payload [Hash] The original Quick Replies payload
    # @return [Hash] Instagram API compatible payload
    def build_quick_replies_payload(payload)
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Building Instagram Quick Replies payload"
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Original payload: #{payload.inspect}"

      instagram_payload = {
        'text' => payload['text'],
        'quick_replies' => build_quick_replies_options(payload['quick_replies'])
      }

      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Built Instagram payload: #{instagram_payload.inspect}"
      instagram_payload
    end

    # Build quick replies options array
    # @param quick_replies [Array] The original quick replies array
    # @return [Array] Instagram API compatible quick replies
    def build_quick_replies_options(quick_replies)
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Building #{quick_replies&.length} Quick Replies options"

      return [] unless quick_replies.is_a?(Array)

      instagram_quick_replies = quick_replies.map.with_index do |quick_reply, index|
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Building quick reply #{index}: #{quick_reply.inspect}"

        instagram_quick_reply = {
          'content_type' => quick_reply['content_type'],
          'title' => quick_reply['title'],
          'payload' => quick_reply['payload']
        }

        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Built quick reply #{index}: #{instagram_quick_reply.inspect}"
        instagram_quick_reply
      end

      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Built #{instagram_quick_replies.length} Instagram quick replies"
      instagram_quick_replies
    end

    # Send Quick Replies message using Instagram Rich Message Service
    # @param payload [Hash] The Quick Replies payload
    # @param message [Message] The message object
    def send_quick_replies(payload, message)
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] === STARTING QUICK REPLIES SEND ==="
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Quick Replies payload: #{payload.inspect}"
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Message ID: #{message.id}, Conversation ID: #{message.conversation.id}"

      begin
        # Build Instagram API compatible Quick Replies structure
        instagram_payload = build_quick_replies_payload(payload)
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Built Instagram payload: #{instagram_payload.inspect}"

        # Create outgoing message for rich message service
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Creating outgoing message for rich message service"
        conversation = message.conversation
        outgoing_message = conversation.messages.create!(
          content: extract_fallback_text({ 'payload' => payload }),
          message_type: :outgoing,
          account_id: conversation.account_id,
          inbox_id: conversation.inbox_id
        )
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Created outgoing message ID: #{outgoing_message.id}"

        # Send using Instagram Rich Message Service
        rich_message_service = Instagram::RichMessageService.new(message: outgoing_message, rich_payload: instagram_payload)
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Created Instagram Rich Message Service"

        # Perform the send operation
        send_start_time = Time.current
        rich_message_service.perform
        send_end_time = Time.current
        
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Quick Replies sent successfully"
        
        # Log performance metrics for the send operation
        log_performance_metrics(
          "Quick Replies Send",
          send_start_time,
          send_end_time,
          message,
          {
            quick_replies_count: payload['quick_replies']&.length || 0,
            text_length: payload['text']&.length || 0
          }
        )

        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] === QUICK REPLIES SEND COMPLETED ==="
        true
      rescue => e
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Quick Replies send failed: #{e.class}: #{e.message}"
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Backtrace: #{e.backtrace.join('\n')}"
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Falling back to text message due to error"
        
        fallback_to_text_message(message, { 'payload' => payload })
        false
      end
    end

    # Logs unknown message format
    # @param message_format [String] The unknown format
    def log_unknown_format(message_format)
      Rails.logger.warn "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Unknown message format received: #{message_format}"
      Rails.logger.warn "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Supported formats: GENERIC_TEMPLATE, BUTTON_TEMPLATE, QUICK_REPLIES"
    end

    # Fallback to text message when rich message processing fails
    # @param message [Message] The original message
    # @param socialwise_data [Hash] The socialwise data for text extraction
    # @return [Boolean] true if fallback was successful
    def fallback_to_text_message(message, socialwise_data)
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Falling back to text message"

      begin
        fallback_text = extract_fallback_text(socialwise_data)
        
        # Validate that fallback maintains conversation flow
        unless validate_fallback_flow(message, fallback_text)
          Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Fallback flow validation failed, using emergency fallback"
          fallback_text = "Message received" # Emergency fallback
        end
        
        conversation = message.conversation
        fallback_message = conversation.messages.create!(
          content: fallback_text,
          message_type: :outgoing,
          account_id: conversation.account_id,
          inbox_id: conversation.inbox_id
        )

        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Fallback text message created successfully: #{fallback_text}"
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Fallback message ID: #{fallback_message.id}, maintains conversation flow"
        true
      rescue => e
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Fallback to text message failed: #{e.class}: #{e.message}"
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Fallback backtrace: #{e.backtrace.join('\n')}"
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] CRITICAL: Fallback failed, conversation flow may be broken"
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
      
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] === PERFORMANCE METRICS ==="
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Operation: #{operation}"
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Duration: #{duration_ms}ms"
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Start time: #{start_time.iso8601}"
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] End time: #{end_time.iso8601}"
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Message ID: #{message.id}"
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Conversation ID: #{message.conversation.id}"
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Account ID: #{message.conversation.account_id}"
      
      # Log additional performance data
      additional_data.each do |key, value|
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] #{key.to_s.humanize}: #{value}"
      end
      
      # Performance warnings
      if duration_ms > 5000
        Rails.logger.warn "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] PERFORMANCE WARNING: #{operation} took #{duration_ms}ms (>5s)"
      elsif duration_ms > 2000
        Rails.logger.warn "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] PERFORMANCE NOTICE: #{operation} took #{duration_ms}ms (>2s)"
      end
      
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] === END PERFORMANCE METRICS ==="
    end

    # Logs success details with comprehensive information
    # @param message_format [String] The message format that was processed
    # @param message [Message] The message object
    # @param payload [Hash] The processed payload
    # @param processing_time [Float] The processing time in milliseconds
    def log_success_details(message_format, message, payload, processing_time)
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] === SUCCESS DETAILS ==="
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Message format: #{message_format}"
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Processing time: #{processing_time}ms"
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Message ID: #{message.id}"
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Conversation ID: #{message.conversation.id}"
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Account ID: #{message.conversation.account_id}"
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Inbox ID: #{message.conversation.inbox_id}"
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Contact ID: #{message.conversation.contact_id}"
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Channel type: #{message.conversation.inbox.channel_type}"
      
      # Log recipient details
      contact = message.conversation.contact
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Recipient name: #{contact.name}"
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Recipient source ID: #{contact.get_source_id(message.conversation.inbox_id)}"
      
      # Log payload summary
      case message_format
      when 'GENERIC_TEMPLATE'
        elements_count = payload['elements']&.length || 0
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Generic Template with #{elements_count} elements"
      when 'BUTTON_TEMPLATE'
        buttons_count = payload['buttons']&.length || 0
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Button Template with #{buttons_count} buttons"
      when 'QUICK_REPLIES'
        replies_count = payload['quick_replies']&.length || 0
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Quick Replies with #{replies_count} options"
      end
      
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] === END SUCCESS DETAILS ==="
    end

    # Tests fallback scenarios to ensure user experience is maintained
    # @param message [Message] The original message
    # @param socialwise_data [Hash] The socialwise data
    # @return [Hash] Test results for different fallback scenarios
    def test_fallback_scenarios(message, socialwise_data)
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Testing fallback scenarios for user experience"
      
      test_results = {
        text_extraction: false,
        flow_validation: false,
        message_creation: false,
        conversation_continuity: false
      }

      begin
        # Test text extraction
        fallback_text = extract_fallback_text(socialwise_data)
        test_results[:text_extraction] = fallback_text.present?
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Text extraction test: #{test_results[:text_extraction]} (text: '#{fallback_text}')"

        # Test flow validation
        test_results[:flow_validation] = validate_fallback_flow(message, fallback_text)
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Flow validation test: #{test_results[:flow_validation]}"

        # Test message creation (dry run)
        conversation = message.conversation
        if conversation&.account_id && conversation&.inbox_id
          test_results[:message_creation] = true
          Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Message creation test: #{test_results[:message_creation]}"
        end

        # Test conversation continuity
        if conversation&.status != 'resolved' && conversation&.messages&.any?
          test_results[:conversation_continuity] = true
          Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Conversation continuity test: #{test_results[:conversation_continuity]}"
        end

        overall_success = test_results.values.all?
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Fallback scenarios test overall: #{overall_success ? 'PASSED' : 'FAILED'}"
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Test results: #{test_results.inspect}"

        test_results
      rescue => e
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Fallback scenarios test failed: #{e.class}: #{e.message}"
        test_results[:error] = e.message
        test_results
      end
    end

    # Validates that fallback maintains conversation flow
    # @param message [Message] The original message
    # @param fallback_text [String] The fallback text to be sent
    # @return [Boolean] true if fallback is valid for conversation flow
    def validate_fallback_flow(message, fallback_text)
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Validating fallback flow for conversation"
      
      # Ensure fallback text is not empty
      unless fallback_text.present?
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Fallback text is empty, this would break conversation flow"
        return false
      end

      # Ensure message and conversation are valid
      unless message&.conversation
        Rails.logger.error "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Invalid message or conversation, cannot maintain flow"
        return false
      end

      # Ensure conversation is still active
      conversation = message.conversation
      if conversation.status == 'resolved'
        Rails.logger.warn "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Conversation is resolved, but fallback will still be sent"
      end

      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Fallback flow validation passed"
      true
    end

    # Extracts meaningful text from failed rich message payloads
    # @param socialwise_data [Hash] The socialwise data
    # @return [String] Extracted text or generic fallback
    def extract_fallback_text(socialwise_data)
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Extracting fallback text from: #{socialwise_data.inspect}"

      return "Message received" unless socialwise_data.is_a?(Hash)

      payload = socialwise_data['payload']
      return "Message received" unless payload.is_a?(Hash)

      # Try to extract text from different payload types
      if payload['text'].present?
        Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Using text field for fallback"
        return payload['text']
      end

      # For Generic Template, try to extract from first element
      if payload['elements'].is_a?(Array) && payload['elements'].first.is_a?(Hash)
        element = payload['elements'].first
        if element['title'].present?
          Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Using first element title for fallback"
          return element['title']
        end
      end

      # Generic fallback
      Rails.logger.info "[SOCIALWISE-INSTAGRAM-DIALOGFLOW] Using generic fallback text"
      "Message received"
    end
  end
end