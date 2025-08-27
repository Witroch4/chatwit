# frozen_string_literal: true

class Messages::WhatsappRendererMapper
  MAX_CARDS = 10
  MAX_BTNS = 3
  MAX_LIST_OPTIONS = 20
  MAX_PAYLOAD_SIZE = 25.kilobytes
  TITLE_LIMIT = 120
  DESCRIPTION_LIMIT = 200
  CACHE_TTL = 1.hour

  # Result structure for mapped payload
  Mapped = Struct.new(:content_type, :content_attributes, :fallback_text)

  class << self
    # Main entry point for mapping WhatsApp interactive payloads to Chatwoot structures
    # @param interactive_payload [Hash] WhatsApp interactive message payload
    # @return [Mapped] Mapped structure with content_type, content_attributes, and fallback_text
    def map(interactive_payload)
      return default_text_mapping(interactive_payload) if invalid_payload?(interactive_payload)
      return default_text_mapping(interactive_payload) if payload_too_large?(interactive_payload)

      # Cache based on payload hash for performance
      cache_key = generate_cache_key(interactive_payload)
      Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
        map_payload(interactive_payload)
      end
    end

    private

    # Validate payload structure and size
    def invalid_payload?(payload)
      return true unless payload.is_a?(Hash)
      return true if payload.empty?
      return true unless payload['type'].present?

      false
    end

    # Check if payload exceeds size limit
    def payload_too_large?(payload)
      payload.to_json.bytesize > MAX_PAYLOAD_SIZE
    end

    # Generate MD5 cache key from payload
    def generate_cache_key(payload)
      hash = Digest::MD5.hexdigest(payload.to_json)
      "whatsapp_mapper:#{hash}"
    end

    # Map payload based on interactive type
    def map_payload(interactive_payload)
      case interactive_payload['type']
      when 'button'
        to_cards_from_button(interactive_payload)
      when 'list'
        to_input_select_from_list(interactive_payload)
      else
        # Default fallback for unknown types
        default_text_mapping(interactive_payload)
      end
    rescue StandardError => e
      Rails.logger.error "[WHATSAPP-MAPPER] Mapping failed: #{e.class}: #{e.message}"
      default_text_mapping(interactive_payload)
    end

    # Convert WhatsApp button template to cards structure
    def to_cards_from_button(payload)
      body_text = payload.dig('body', 'text').to_s.strip
      header = payload['header']
      footer_text = payload.dig('footer', 'text').to_s.strip
      buttons = Array(payload.dig('action', 'buttons')).first(MAX_BTNS)

      return default_text_mapping(payload) if body_text.blank? && buttons.empty?

      # Build card item
      card_item = {
        'title' => body_text.present? ? body_text.truncate(TITLE_LIMIT) : nil
      }.compact

      # Add description from footer
      if footer_text.present?
        card_item['description'] = footer_text.truncate(DESCRIPTION_LIMIT)
      end

      # Add image if present in header
      if header&.dig('type') == 'image'
        image_url = header.dig('image', 'link') || header.dig('image', 'id')
        if image_url.present?
          safe_image_url = safe_url(image_url)
          card_item['media_url'] = safe_image_url if safe_image_url
        end
      end

      # Add buttons as actions
      actions = map_buttons(buttons)
      card_item['actions'] = actions if actions.any?

      # Generate fallback text
      fallback = generate_fallback_text_from_button(body_text, footer_text, buttons)

      Mapped.new('cards', { 'items' => [card_item] }, fallback)
    end

    # Convert WhatsApp list template to input_select structure
    def to_input_select_from_list(payload)
      body_text = payload.dig('body', 'text').to_s.strip
      sections = Array(payload.dig('action', 'sections'))
      
      return default_text_mapping(payload) if sections.empty?

      # Extract all rows from all sections
      items = []
      sections.each do |section|
        section_rows = Array(section['rows'])
        section_rows.each do |row|
          title = row['title'].to_s.strip
          row_id = row['id'].to_s.strip
          description = row['description'].to_s.strip

          next if title.blank? || row_id.blank?

          item = {
            'title' => title.truncate(TITLE_LIMIT),
            'value' => row_id
          }

          # Add description if present
          if description.present?
            item['description'] = description.truncate(DESCRIPTION_LIMIT)
          end

          items << item
        end
      end

      # Limit number of options
      items = items.first(MAX_LIST_OPTIONS)
      return default_text_mapping(payload) if items.empty?

      # Generate fallback text
      text = body_text.presence || 'Select an option'
      fallback = "#{text} (#{items.length} options)"

      Mapped.new('input_select', { 'items' => items }, fallback)
    end

    # Map WhatsApp buttons to Chatwoot actions
    def map_buttons(buttons)
      return [] unless buttons.is_a?(Array)

      buttons.map do |button|
        next unless button.is_a?(Hash)

        button_type = button['type'].to_s
        
        case button_type
        when 'reply'
          title = button.dig('reply', 'title').to_s.strip
          button_id = button.dig('reply', 'id').to_s.strip
          
          next if title.blank? || button_id.blank?

          {
            'type' => 'postback',
            'text' => title.truncate(50),
            'payload' => button_id
          }
        when 'url'
          title = button['title'].to_s.strip
          url = button['url'].to_s.strip
          
          next if title.blank? || url.blank?
          
          safe_button_url = safe_url(url)
          next unless safe_button_url

          {
            'type' => 'link',
            'text' => title.truncate(50),
            'uri' => safe_button_url
          }
        end
      end.compact
    end

    # Sanitize and validate URLs
    def safe_url(url)
      return nil if url.blank?

      # Parse and validate URL
      uri = URI.parse(url.strip)
      return nil unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

      # Basic security checks
      return nil if uri.host.blank?
      return nil if uri.host.match?(/localhost|127\.0\.0\.1|0\.0\.0\.0/i)

      uri.to_s
    rescue URI::InvalidURIError => e
      Rails.logger.warn "[WHATSAPP-MAPPER] Invalid URL: #{url} - #{e.message}"
      nil
    end

    # Generate fallback text from button template
    def generate_fallback_text_from_button(body_text, footer_text, buttons)
      parts = []
      
      parts << body_text if body_text.present?
      parts << footer_text if footer_text.present?
      
      # Add button titles for context
      if buttons.any?
        button_titles = buttons.map do |btn|
          btn.dig('reply', 'title') || btn['title']
        end.compact
        
        if button_titles.any?
          parts << "Options: #{button_titles.join(', ')}"
        end
      end
      
      return 'WhatsApp interactive message' if parts.empty?
      parts.join(' | ')
    end

    # Generate fallback text from list template
    def generate_fallback_text_from_list(body_text, sections)
      parts = []
      
      parts << body_text if body_text.present?
      
      # Add list options for context
      option_titles = []
      sections.each do |section|
        section['rows']&.each { |row| option_titles << row['title'] }
      end
      
      if option_titles.any?
        # Limit to first few options to avoid too long text
        limited_options = option_titles.first(5)
        suffix = option_titles.length > 5 ? "... (#{option_titles.length} total)" : ""
        parts << "Options: #{limited_options.join(', ')}#{suffix}"
      end
      
      return 'WhatsApp interactive message' if parts.empty?
      parts.join(' | ')
    end

    # Default text mapping for unsupported or invalid payloads
    def default_text_mapping(payload)
      text = extract_text_from_payload(payload)
      Mapped.new('text', {}, text)
    end

    # Extract text content from various payload formats
    def extract_text_from_payload(payload)
      return 'WhatsApp interactive message' unless payload.is_a?(Hash)

      # Try different text fields
      text = payload.dig('body', 'text').to_s.strip.presence ||
             payload.dig('footer', 'text').to_s.strip.presence ||
             payload.dig('action', 'buttons')&.first&.dig('reply', 'title').to_s.strip.presence ||
             payload.dig('action', 'sections')&.first&.dig('rows')&.first&.dig('title').to_s.strip.presence ||
             'WhatsApp interactive message'

      text.truncate(500)
    end
  end
end