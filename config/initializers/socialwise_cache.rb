# frozen_string_literal: true

# SocialWise Cache Initialization
# Preloads WhatsApp inbox cache for better webhook performance

Rails.application.config.after_initialize do
  # Only preload cache in production and staging environments
  # Skip in development, test, and during migrations/seeds
  if Rails.env.production? || Rails.env.staging?
    # Skip during database migrations or when database is not ready
    next unless ActiveRecord::Base.connection.table_exists?('inboxes')
    next unless ActiveRecord::Base.connection.table_exists?('channels')
    
    # Preload cache in a background thread to not block application startup
    Thread.new do
      begin
        Rails.logger.info "[SOCIALWISE] Starting cache preload in background thread"
        
        # Wait a bit for the application to fully initialize
        sleep(5)
        
        # Preload WhatsApp inbox cache
        Integrations::Socialwise::WebhookEnhancerService.preload_whatsapp_inbox_cache
        
        Rails.logger.info "[SOCIALWISE] Cache preload completed successfully"
      rescue => e
        Rails.logger.error "[SOCIALWISE] Cache preload failed: #{e.message}"
        Rails.logger.error "[SOCIALWISE] Backtrace: #{e.backtrace.join('\n')}"
      end
    end
  else
    Rails.logger.info "[SOCIALWISE] Skipping cache preload in #{Rails.env} environment"
  end
end