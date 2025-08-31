class Whatsapp::SendStickerService
  MEDIA_CACHE_TTL = 30.days
  MEDIA_CACHE_PREFIX = 'whatsapp_media_id'
  
  # Custom error classes for better error handling
  class StickerSendError < StandardError; end
  class MediaUploadError < StickerSendError; end
  class WhatsAppApiError < StickerSendError; end
  class InvalidStickerDataError < StickerSendError; end
  class ConversationNotFoundError < StickerSendError; end
  
  def initialize(conversation:, sticker_data:, user:)
    @conversation = conversation
    @sticker_data = sticker_data
    @user = user
    @channel = conversation.inbox.channel
    @metrics_service = StickerPerformanceMetricsService.instance
    
    # CRITICAL DEBUG: Log initialization details
    Rails.logger.info "WhatsApp SendStickerService: Initialized with conversation #{@conversation.id}"
    Rails.logger.info "  - Account ID: #{@conversation.account_id}"
    Rails.logger.info "  - Inbox ID: #{@conversation.inbox_id}"
    Rails.logger.info "  - Contact ID: #{@conversation.contact.id}"
    Rails.logger.info "  - User ID: #{@user.id}"
    Rails.logger.info "  - Sticker URL: #{@sticker_data[:url]}"
  end

  def perform
    start_time = Time.current
    
    Rails.logger.info "WhatsApp SendStickerService: Starting sticker send process for sticker ID #{@sticker_data[:id]} (#{@sticker_data[:provider]})"
    Rails.logger.info "WhatsApp SendStickerService: Sticker URL: #{@sticker_data[:url]}"
    
    begin
      validate_inputs!
      
      # 1. Obtain media_id (with 30-day cache)
      media_id = fetch_or_upload_media
      return build_error_response('MEDIA_UPLOAD_FAILED', 'Failed to upload sticker to WhatsApp') unless media_id

      # 2. Create message using existing enum
      message = create_sticker_message

      # 3. Send via WhatsApp
      whatsapp_start_time = Time.current
      response = send_to_whatsapp(media_id)
      whatsapp_response_time = (Time.current - whatsapp_start_time) * 1000

      if response[:success]
        # 🎯 UPDATE SOURCE_ID FOR STATUS CHECKS (follows native SendOnWhatsappService pattern)
        if response[:message_id].present?
          message.update!(source_id: response[:message_id])
          Rails.logger.info "WhatsApp SendStickerService: Updated message #{message.id} with source_id: #{response[:message_id]}"
          Rails.logger.info "WhatsApp SendStickerService: Message status after update: #{message.reload.status}"
          Rails.logger.info "WhatsApp SendStickerService: Message source_id after update: #{message.reload.source_id}"
        else
          Rails.logger.warn "WhatsApp SendStickerService: No message_id returned from WhatsApp API"
        end
        
        # Track successful sticker usage
        total_response_time = (Time.current - start_time) * 1000
        @metrics_service.track_sticker_usage(
          provider: @sticker_data[:provider],
          account_id: @conversation.account_id,
          user_id: @user.id,
          response_time: total_response_time
        )
        
        # Track WhatsApp API performance
        @metrics_service.track_api_performance(
          api_name: 'whatsapp_send_sticker',
          response_time: whatsapp_response_time,
          success: true
        )
        
        # 4. Record as recent sticker for user
        record_recent_sticker
        { success: true, message_id: message.id, source_id: response[:message_id] }
      else
        # Track failed WhatsApp API call
        @metrics_service.track_api_performance(
          api_name: 'whatsapp_send_sticker',
          response_time: whatsapp_response_time,
          success: false
        )
        
        message.destroy # Remove message if sending failed
        build_error_response_from_whatsapp(response)
      end
    rescue StandardError => e
      # Track failed sticker usage
      total_response_time = (Time.current - start_time) * 1000
      @metrics_service.track_api_performance(
        api_name: 'whatsapp_send_sticker',
        response_time: total_response_time,
        success: false
      )
      raise e
    end
  rescue InvalidStickerDataError => e
    Rails.logger.error "WhatsApp SendStickerService validation error: #{e.message}"
    
    StickerErrorLoggerService.log_error(
      error_code: 'INVALID_STICKER_DATA',
      error_message: e.message,
      context: { sticker_url: @sticker_data&.dig(:url), service: 'SendStickerService' },
      user: @user,
      account: @conversation&.account
    )
    
    build_error_response('INVALID_STICKER_DATA', e.message)
  rescue ConversationNotFoundError => e
    Rails.logger.error "WhatsApp SendStickerService conversation error: #{e.message}"
    
    StickerErrorLoggerService.log_error(
      error_code: 'CONVERSATION_NOT_FOUND',
      error_message: e.message,
      context: { service: 'SendStickerService' },
      user: @user,
      account: @conversation&.account
    )
    
    build_error_response('CONVERSATION_NOT_FOUND', 'Conversation not found or not accessible')
  rescue MediaUploadError => e
    Rails.logger.error "WhatsApp SendStickerService media upload error: #{e.message}"
    
    StickerErrorLoggerService.log_error(
      error_code: 'MEDIA_UPLOAD_FAILED',
      error_message: e.message,
      context: { sticker_url: @sticker_data&.dig(:url), service: 'SendStickerService' },
      user: @user,
      account: @conversation&.account
    )
    
    build_error_response('MEDIA_UPLOAD_FAILED', 'Failed to upload sticker. Please try again.')
  rescue WhatsAppApiError => e
    Rails.logger.error "WhatsApp SendStickerService API error: #{e.message}"
    
    StickerErrorLoggerService.log_error(
      error_code: 'WHATSAPP_API_ERROR',
      error_message: e.message,
      context: { service: 'SendStickerService' },
      user: @user,
      account: @conversation&.account
    )
    
    build_error_response('WHATSAPP_API_ERROR', 'WhatsApp service temporarily unavailable. Please try again.')
  rescue StandardError => e
    Rails.logger.error "WhatsApp SendStickerService unexpected error: #{e.message}\n#{e.backtrace.join("\n")}"
    
    StickerErrorLoggerService.log_error(
      error_code: 'UNKNOWN_ERROR',
      error_message: e.message,
      context: { 
        sticker_url: @sticker_data&.dig(:url), 
        service: 'SendStickerService',
        backtrace: e.backtrace&.first(5)
      },
      user: @user,
      account: @conversation&.account
    )
    
    build_error_response('UNKNOWN_ERROR', 'An unexpected error occurred. Please try again.')
  end

  private

  def validate_inputs!
    raise ConversationNotFoundError, 'Conversation is required' unless @conversation
    raise ConversationNotFoundError, 'Channel not found for conversation' unless @channel
    raise InvalidStickerDataError, 'Sticker data is required' unless @sticker_data
    raise InvalidStickerDataError, 'Sticker URL is required' unless @sticker_data[:url].present?
    raise InvalidStickerDataError, 'User is required' unless @user
    
    # Validate conversation is WhatsApp
    unless @channel.is_a?(Channel::Whatsapp)
      raise InvalidStickerDataError, 'Stickers can only be sent in WhatsApp conversations'
    end
    
    # Validate contact_inbox exists and has source_id (phone number)
    unless @conversation.contact_inbox&.source_id.present?
      raise ConversationNotFoundError, 'No phone number found for this conversation'
    end
    
    # Validate sticker URL format
    unless @sticker_data[:url] =~ URI::DEFAULT_PARSER.make_regexp(%w[http https])
      raise InvalidStickerDataError, 'Invalid sticker URL format'
    end
    
    # Validate WhatsApp provider configuration
    config = @channel.provider_config
    unless config&.dig('api_key').present?
      raise InvalidStickerDataError, 'WhatsApp API key not configured'
    end
    
    unless config&.dig('phone_number_id').present?
      raise InvalidStickerDataError, 'WhatsApp phone number ID not configured'
    end
    
    Rails.logger.info "WhatsApp SendStickerService: Configuration validated successfully"
    Rails.logger.info "WhatsApp SendStickerService: Target phone number: #{@conversation.contact_inbox.source_id}"
  end

  def fetch_or_upload_media
    cache_key = generate_media_cache_key(@sticker_data[:url])
    
    # Check if cache exists using Redis::Alfred (Chatwoot pattern)
    cached_media_id = Redis::Alfred.get(cache_key)
    cache_exists = cached_media_id.present?
    
    Rails.logger.info "WhatsApp SendStickerService: Cache check for key #{cache_key.split(':').last[0..8]}... - EXISTS: #{cache_exists}"
    
    # Track cache metrics
    @metrics_service.track_cache_hit(cache_type: 'whatsapp_media', hit: cache_exists)

    if cache_exists
      Rails.logger.info "WhatsApp SendStickerService: CACHE HIT - Using cached media_id for sticker ID #{@sticker_data[:id]}"
      return cached_media_id
    end

    # Cache miss - upload media
    Rails.logger.info "WhatsApp SendStickerService: CACHE MISS - Uploading media to WhatsApp for sticker ID #{@sticker_data[:id]}"
    upload_start_time = Time.current
    
    media_id = upload_media_to_whatsapp
    
    if media_id
      # Track media upload performance
      upload_response_time = (Time.current - upload_start_time) * 1000
      @metrics_service.track_api_performance(
        api_name: 'whatsapp_media_upload',
        response_time: upload_response_time,
        success: true
      )
      
      # Save to cache using Redis::Alfred (Chatwoot pattern)
      Redis::Alfred.setex(cache_key, media_id, MEDIA_CACHE_TTL)
      
      Rails.logger.info "WhatsApp SendStickerService: Media uploaded successfully, media_id: #{media_id}, cached for #{MEDIA_CACHE_TTL / 1.day} days"
      Rails.logger.info "WhatsApp SendStickerService: CACHE WRITE - Saved media_id #{media_id} to key #{cache_key.split(':').last[0..8]}..."
      
      # Verify cache was saved (Chatwoot pattern)
      verification_value = Redis::Alfred.get(cache_key)
      if verification_value == media_id
        Rails.logger.info "WhatsApp SendStickerService: CACHE VERIFICATION - Successfully cached value: #{verification_value}"
      else
        Rails.logger.error "WhatsApp SendStickerService: CACHE VERIFICATION FAILED - Expected: #{media_id}, Got: #{verification_value}"
      end
      
      media_id
    else
      @metrics_service.track_cache_hit(cache_type: 'whatsapp_media', hit: false, error: true)
      nil
    end
  rescue StandardError => e
    Rails.logger.error "WhatsApp SendStickerService media fetch error: #{e.message}"
    
    # Track failed media upload
    upload_response_time = (Time.current - upload_start_time) * 1000 if defined?(upload_start_time)
    @metrics_service.track_api_performance(
      api_name: 'whatsapp_media_upload',
      response_time: upload_response_time || 0,
      success: false
    ) if upload_response_time
    
    raise MediaUploadError, "Failed to fetch or upload media: #{e.message}"
  end

  def create_sticker_message
    # CRITICAL DEBUG: Log conversation details before creating message
    Rails.logger.info "WhatsApp SendStickerService: Creating message for conversation #{@conversation.id}"
    Rails.logger.info "  - Account ID: #{@conversation.account_id}"
    Rails.logger.info "  - Inbox ID: #{@conversation.inbox_id}"
    Rails.logger.info "  - Contact ID: #{@conversation.contact.id}"
    Rails.logger.info "  - Contact Phone: #{@conversation.contact.phone_number}"
    Rails.logger.info "  - ContactInbox Source ID: #{@conversation.contact_inbox.source_id}"
    Rails.logger.info "  - User ID: #{@user.id} (#{@user.name})"
    
    # 🎯 USE NATIVE MESSAGEBUILDER PATTERN - This ensures correct sender attribution
    message_params = ActionController::Parameters.new({
      content: "Sticker: #{@sticker_data[:alt]}",
      content_type: 'sticker', # Uses existing enum
      content_attributes: {
        sticker_data: @sticker_data
      },
      message_type: 'outgoing', # String, not symbol for MessageBuilder
      additional_attributes: { 
        skip_send_reply: true # Prevents duplicate sending - CRITICAL FLAG!
      }
    })
    
    # Use MessageBuilder to ensure proper sender attribution (follows native pattern)
    builder = Messages::MessageBuilder.new(@user, @conversation, message_params)
    message = builder.perform
    
    # CRITICAL DEBUG: Verify the message was created correctly with proper sender
    Rails.logger.info "WhatsApp SendStickerService: Message created with ID #{message.id}"
    Rails.logger.info "  - Message conversation_id: #{message.conversation_id}"
    Rails.logger.info "  - Expected conversation_id: #{@conversation.id}"
    Rails.logger.info "  - Match: #{message.conversation_id == @conversation.id}"
    Rails.logger.info "  - Sender: #{message.sender.class.name} ID #{message.sender.id} (#{message.sender.try(:name) || message.sender.try(:display_name)})"
    Rails.logger.info "  - Expected sender: User ID #{@user.id} (#{@user.name})"
    
    if message.conversation_id != @conversation.id
      Rails.logger.error "CRITICAL ERROR: Message created in wrong conversation!"
      Rails.logger.error "  - Expected: #{@conversation.id}"
      Rails.logger.error "  - Actual: #{message.conversation_id}"
      raise ConversationNotFoundError, "Message created in wrong conversation (#{message.conversation_id} instead of #{@conversation.id})"
    end
    
    # Verify sender is correct (should be the user, not a bot)
    if message.sender != @user
      Rails.logger.error "CRITICAL ERROR: Message has wrong sender!"
      Rails.logger.error "  - Expected: User ID #{@user.id} (#{@user.name})"
      Rails.logger.error "  - Actual: #{message.sender.class.name} ID #{message.sender.id}"
      # Don't raise error, but log for debugging
    end
    
    message
  end

  def send_to_whatsapp(media_id)
    Rails.logger.info "WhatsApp SendStickerService: Sending sticker to WhatsApp using media_id: #{media_id}"
    
    # Use the same phone number extraction logic as SendOnWhatsappService
    phone_number = @conversation.contact_inbox.source_id
    
    # DEBUG: Log detailed conversation information
    Rails.logger.info "WhatsApp SendStickerService DEBUG:"
    Rails.logger.info "  - Conversation ID: #{@conversation.id}"
    Rails.logger.info "  - Contact ID: #{@conversation.contact.id}"
    Rails.logger.info "  - Contact Phone: #{@conversation.contact.phone_number}"
    Rails.logger.info "  - ContactInbox ID: #{@conversation.contact_inbox.id}"
    Rails.logger.info "  - ContactInbox Source ID: #{@conversation.contact_inbox.source_id}"
    Rails.logger.info "  - Inbox ID: #{@conversation.inbox.id}"
    Rails.logger.info "  - Channel ID: #{@channel.id}"
    Rails.logger.info "  - Using phone number: #{phone_number}"
    
    # Validate phone number before sending
    if phone_number.blank?
      Rails.logger.error "WhatsApp SendStickerService: No phone number found for conversation #{@conversation.id}"
      return { success: false, error: 'No phone number found for this conversation' }
    end
    
    result = @channel.provider_service.send_sticker_message(
      phone_number,
      media_id
    )
    
    Rails.logger.info "WhatsApp SendStickerService: Provider result: #{result.inspect}"
    
    if result
      { success: true, message_id: result }
    else
      { success: false, error: 'Failed to send sticker message' }
    end
  end

  def record_recent_sticker
    # Uses ui_settings from existing User model
    # NOTE: For high concurrency, consider moving to background job
    recent_stickers = @user.ui_settings&.dig('recent_stickers') || []

    # Remove if already exists and add to beginning
    recent_stickers.reject! { |s| s['url'] == @sticker_data[:url] }
    recent_stickers.unshift({
      url: @sticker_data[:url],
      alt: @sticker_data[:alt],
      provider: @sticker_data[:provider],
      used_at: Time.current.iso8601
    })

    # Keep only the 20 most recent
    recent_stickers = recent_stickers.first(20)

    # Update ui_settings (uses update_column for performance)
    ui_settings = @user.ui_settings || {}
    ui_settings['recent_stickers'] = recent_stickers
    @user.update_column(:ui_settings, ui_settings)
  end

  def get_media_data_efficiently
    # Try to get attachment directly from Active Storage (more efficient than HTTP download)
    if @sticker_data[:url].include?('rails/active_storage') && @sticker_data[:id]
      attachment = Attachment.find_by(id: @sticker_data[:id])
      if attachment&.file&.attached?
        Rails.logger.info "WhatsApp SendStickerService: Using direct file access for attachment #{attachment.id}"
        return attachment.file.blob.download.force_encoding('BINARY')
      end
    end
    
    # Fallback to HTTP download using sticker-specific URL method
    Rails.logger.info "WhatsApp SendStickerService: Falling back to HTTP download from: #{@sticker_data[:url]}"
    download_via_http
  end

  def download_via_http
    response = HTTParty.get(@sticker_data[:url], {
      timeout: 30,
      follow_redirects: true, # Important for redirect URLs
      headers: {
        'User-Agent' => 'Chatwoot/1.0'
      }
    })
    
    Rails.logger.info "WhatsApp SendStickerService: Download response status: #{response.code}"
    
    unless response.success?
      Rails.logger.error "WhatsApp SendStickerService: Download failed with status #{response.code}"
      raise MediaUploadError, "Failed to download sticker: HTTP #{response.code} - #{response.message}"
    end
    
    # CRITICAL FIX: Force binary encoding to avoid character encoding issues
    response.body.force_encoding('BINARY')
  end

  def optimize_sticker_for_whatsapp(media_data)
    Rails.logger.info "WhatsApp SendStickerService: Starting sticker optimization"
    
    # Create a temporary file for optimization
    temp_file = Tempfile.new(['sticker_optimize', '.webp'])
    temp_file.binmode
    temp_file.write(media_data)
    temp_file.rewind
    
    begin
      # Use the existing StickerImageOptimizerService with correct parameters
      optimizer = StickerImageOptimizerService.new(file: temp_file, account_id: @conversation.account_id)
      
      # Optimize the sticker using the direct method
      optimized_path = optimizer.optimize_for_whatsapp(temp_file.path)
      
      # Read the optimized file
      optimized_data = File.binread(optimized_path).force_encoding('BINARY')
      
      Rails.logger.info "WhatsApp SendStickerService: Optimization complete - #{media_data.bytesize} -> #{optimized_data.bytesize} bytes"
      
      # Clean up optimized file
      File.delete(optimized_path) if File.exist?(optimized_path)
      
      optimized_data
    rescue StandardError => e
      Rails.logger.warn "WhatsApp SendStickerService: Optimization failed: #{e.message}, using original"
      # If optimization fails, return original data
      media_data
    ensure
      temp_file.close
      temp_file.unlink
    end
  end

  def upload_media_to_whatsapp
    Rails.logger.info "WhatsApp SendStickerService: Preparing sticker for upload: #{@sticker_data[:url]}"
    
    # Try to get file directly from Active Storage first (more efficient)
    raw_media_data = get_media_data_efficiently
    
    Rails.logger.info "WhatsApp SendStickerService: Raw file size: #{raw_media_data.bytesize} bytes"
    
    # CRITICAL: Optimize sticker for WhatsApp before upload
    optimized_media_data = optimize_sticker_for_whatsapp(raw_media_data)
    
    Rails.logger.info "WhatsApp SendStickerService: Optimized file size: #{optimized_media_data.bytesize} bytes"
    
    # Validate optimized file size (WhatsApp limits)
    if optimized_media_data.bytesize > 500.kilobytes
      raise MediaUploadError, 'Sticker file too large after optimization (max 500KB)'
    end
    
    if optimized_media_data.bytesize < 100.bytes
      raise MediaUploadError, 'Sticker file too small or corrupted after optimization'
    end

    Rails.logger.info "WhatsApp SendStickerService: Uploading optimized sticker to WhatsApp..."
    
    # Upload to WhatsApp with correct MIME type
    media_id = @channel.provider_service.upload_media(optimized_media_data, 'image/webp')
    
    unless media_id
      raise MediaUploadError, 'WhatsApp media upload returned no media ID'
    end
    
    Rails.logger.info "WhatsApp SendStickerService: Successfully uploaded media, ID: #{media_id}"
    media_id
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.error "WhatsApp SendStickerService: Download timeout: #{e.message}"
    raise MediaUploadError, "Download timeout: #{e.message}"
  rescue SocketError, Errno::ECONNREFUSED => e
    Rails.logger.error "WhatsApp SendStickerService: Connection failed: #{e.message}"
    raise MediaUploadError, "Connection failed: #{e.message}"
  rescue HTTParty::Error => e
    Rails.logger.error "WhatsApp SendStickerService: HTTP error: #{e.message}"
    raise MediaUploadError, "HTTP error: #{e.message}"
  end

  def build_error_response(error_code, message)
    {
      success: false,
      error: message,
      error_code: error_code,
      user_message: get_user_friendly_message(error_code)
    }
  end

  def build_error_response_from_whatsapp(whatsapp_response)
    error_code = map_whatsapp_error_code(whatsapp_response[:error])
    {
      success: false,
      error: whatsapp_response[:error],
      error_code: error_code,
      user_message: get_user_friendly_message(error_code)
    }
  end

  def map_whatsapp_error_code(error_message)
    case error_message&.downcase
    when /rate limit/i, /too many requests/i
      'WHATSAPP_RATE_LIMIT'
    when /invalid media/i, /unsupported media/i
      'WHATSAPP_INVALID_MEDIA'
    when /recipient not found/i, /invalid phone/i
      'WHATSAPP_INVALID_RECIPIENT'
    when /authentication/i, /unauthorized/i
      'WHATSAPP_AUTH_ERROR'
    when /quota exceeded/i
      'WHATSAPP_QUOTA_EXCEEDED'
    else
      'WHATSAPP_UNKNOWN_ERROR'
    end
  end

  def get_user_friendly_message(error_code)
    case error_code
    when 'INVALID_STICKER_DATA'
      'Invalid sticker data. Please try selecting a different sticker.'
    when 'MEDIA_UPLOAD_FAILED'
      'Failed to upload sticker. Please check your internet connection and try again.'
    when 'WHATSAPP_RATE_LIMIT'
      'Too many messages sent. Please wait a moment before sending another sticker.'
    when 'WHATSAPP_INVALID_MEDIA'
      'This sticker format is not supported. Please try a different sticker.'
    when 'WHATSAPP_INVALID_RECIPIENT'
      'Unable to send message to this contact. Please verify the phone number.'
    when 'WHATSAPP_AUTH_ERROR'
      'WhatsApp authentication error. Please contact your administrator.'
    when 'WHATSAPP_QUOTA_EXCEEDED'
      'WhatsApp message quota exceeded. Please try again later.'
    when 'CONVERSATION_NOT_FOUND'
      'Conversation not found. Please refresh the page and try again.'
    else
      'Unable to send sticker. Please try again.'
    end
  end

  def generate_media_cache_key(url)
    url_hash = Digest::MD5.hexdigest(url)
    cache_key = format(Redis::RedisKeys::WHATSAPP_MEDIA_CACHE, channel_id: @channel.id, url_hash: url_hash)
    Rails.logger.info "WhatsApp SendStickerService: CACHE KEY GENERATION:"
    Rails.logger.info "  - URL: #{url}"
    Rails.logger.info "  - URL Hash: #{url_hash}"
    Rails.logger.info "  - Channel ID: #{@channel.id}"
    Rails.logger.info "  - Full Cache Key: #{cache_key}"
    cache_key
  end



  def self.invalidate_media_cache(url, channel_id = nil)
    if channel_id
      # Invalidate for specific channel using Redis::Alfred (Chatwoot pattern)
      url_hash = Digest::MD5.hexdigest(url)
      cache_key = format(Redis::RedisKeys::WHATSAPP_MEDIA_CACHE, channel_id: channel_id, url_hash: url_hash)
      Rails.logger.info "WhatsApp SendStickerService: Invalidating specific cache key: #{cache_key.split(':').last[0..8]}..."
      Redis::Alfred.delete(cache_key)
    else
      # For multiple channels, we need to iterate (Redis::Alfred doesn't have delete_matched)
      # This is less efficient but follows Chatwoot patterns
      Rails.logger.info "WhatsApp SendStickerService: Invalidating cache for all channels (URL: #{url[0..20]}...)"
      # Note: In a real scenario, you might want to track channel IDs or use a different approach
      # For now, we'll log this case and handle it when needed
      Rails.logger.warn "WhatsApp SendStickerService: Bulk cache invalidation not implemented with Redis::Alfred - consider tracking channel IDs"
    end
    Rails.logger.info "WhatsApp SendStickerService: Media cache invalidated successfully"
  end
end