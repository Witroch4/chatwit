# StickerUploader handles image processing for custom stickers
# Converts images to WebP format with 512x512 dimensions and validates file size
require 'mini_magick'

class StickerUploader
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Validations

  attribute :file
  attribute :pack_name, :string
  attribute :tags, default: []

  validates :file, presence: true
  validates :pack_name, presence: true, length: { minimum: 1, maximum: 50 }
  validate :validate_image_file
  validate :validate_file_size

  MAX_FILE_SIZE = 5.megabytes # Input file size limit
  MAX_OUTPUT_SIZE = 100.kilobytes # WhatsApp sticker size limit
  STICKER_DIMENSIONS = 512

  def process_and_validate
    return false unless valid?

    begin
      @processed_file = process_image
      validate_processed_file
      valid?
    rescue StandardError => e
      errors.add(:file, "Processing failed: #{e.message}")
      false
    end
  end

  def processed_file
    @processed_file
  end

  def processed_filename
    "sticker_#{SecureRandom.hex(8)}.webp"
  end

  private

  def validate_image_file
    return unless file

    unless file.respond_to?(:content_type) && file.content_type&.start_with?('image/')
      errors.add(:file, 'must be an image file')
      return
    end

    # Check if it's a supported image format
    supported_formats = %w[image/jpeg image/jpg image/png image/gif image/webp image/bmp image/tiff]
    unless supported_formats.include?(file.content_type.downcase)
      errors.add(:file, 'format not supported. Please use JPEG, PNG, GIF, WebP, BMP, or TIFF')
    end
  end

  def validate_file_size
    return unless file&.respond_to?(:size)

    if file.size > MAX_FILE_SIZE
      errors.add(:file, "is too large. Maximum size is #{MAX_FILE_SIZE / 1.megabyte}MB")
    end
  end

  def process_image
    # Detect if we need special handling for animation/transparency
    needs_optimizer = needs_special_processing?
    
    Rails.logger.info "[STICKER_UPLOADER] Processing sticker: content_type=#{file.content_type}, needs_optimizer=#{needs_optimizer}"
    
    if needs_optimizer
      Rails.logger.info "[STICKER_UPLOADER] 🎬 Using StickerImageOptimizerService for animation/transparency preservation"
      process_with_optimizer
    else
      Rails.logger.info "[STICKER_UPLOADER] ⚡ Using fast Vips processing for static image"
      process_with_vips
    end
  end

  def needs_special_processing?
    return false unless file.respond_to?(:content_type)
    
    content_type = file.content_type&.downcase
    
    # Always use optimizer for GIFs (likely animated)
    return true if content_type == 'image/gif'
    
    # For WebP, we need to check if it's animated
    # For PNG, check if it has transparency that we want to preserve
    if content_type == 'image/webp'
      # WebP could be animated - use optimizer to be safe
      Rails.logger.info "[STICKER_UPLOADER] 🔍 WebP detected - assuming potential animation"
      return true
    end
    
    if content_type == 'image/png'
      # PNG has transparency - use optimizer to preserve alpha
      Rails.logger.info "[STICKER_UPLOADER] 🔍 PNG detected - preserving potential transparency"
      return true
    end
    
    # JPEG and other formats can use fast processing
    false
  end

  def process_with_optimizer
    start_time = Time.current
    
    # Create temporary input file for the optimizer
    temp_input = Tempfile.new(['sticker_input', File.extname(file.original_filename || '.tmp')])
    temp_input.binmode
    
    # Write file content to temp file
    file.rewind if file.respond_to?(:rewind)
    temp_input.write(file.read)
    temp_input.close
    
    Rails.logger.info "[STICKER_UPLOADER] 📝 Created temp input: #{temp_input.path}"
    
    # Check original frames before processing
    begin
      original_image = MiniMagick::Image.open(temp_input.path)
      original_frames = original_image.frames.count
      Rails.logger.info "🎬 [FRAMES] UPLOADER Input: #{original_frames} frames"
    rescue => e
      Rails.logger.warn "Could not detect original frames in uploader: #{e.message}"
      original_frames = "unknown"
    end
    
    # Use the optimizer service
    optimizer = StickerImageOptimizerService.new(
      file: File.open(temp_input.path, 'rb'),
      account_id: nil # We don't have account context in uploader
    )
    
    result = optimizer.process
    processing_time = (Time.current - start_time) * 1000
    
    if result[:success]
      Rails.logger.info "[STICKER_UPLOADER] ✅ Optimizer success: #{result[:final_size]} bytes, #{processing_time.round(2)}ms"
      Rails.logger.info "[STICKER_UPLOADER] 📊 Animation: #{result[:is_animated]}, Transparency: #{result[:has_transparency]}"
      Rails.logger.info "[STICKER_UPLOADER] 🗜️ Compression: #{result[:compression_ratio]}%"
      
      # Check frames after processing
      begin
        if result[:processed_file].respond_to?(:tempfile)
          processed_image = MiniMagick::Image.open(result[:processed_file].tempfile.path)
        elsif result[:processed_file].respond_to?(:path)
          processed_image = MiniMagick::Image.open(result[:processed_file].path)
        end
        
        if processed_image
          processed_frames = processed_image.frames.count
          Rails.logger.info "🎬 [FRAMES] UPLOADER Output: #{processed_frames} frames (original: #{original_frames})"
        end
      rescue => e
        Rails.logger.warn "Could not detect processed frames in uploader: #{e.message}"
      end
      
      result[:processed_file]
    else
      Rails.logger.error "[STICKER_UPLOADER] ❌ Optimizer failed: #{result[:error]}, falling back to Vips"
      process_with_vips
    end
  ensure
    temp_input&.unlink
  end

  def process_with_vips
    start_time = Time.current
    
    # Use ImageProcessing with Vips for better performance and WebP support
    processed = ImageProcessing::Vips
      .source(file)
      .resize_to_fill(STICKER_DIMENSIONS, STICKER_DIMENSIONS, crop: :centre)
      .convert('webp')
      .saver(quality: 85, effort: 6) # Good quality with reasonable compression
      .call

    processing_time = (Time.current - start_time) * 1000
    Rails.logger.info "[STICKER_UPLOADER] ⚡ Vips processing completed in #{processing_time.round(2)}ms"

    # Create a temporary file with the processed image
    temp_file = Tempfile.new(['processed_sticker', '.webp'])
    temp_file.binmode
    temp_file.write(processed.read)
    temp_file.rewind
    
    file_size = temp_file.size
    Rails.logger.info "[STICKER_UPLOADER] 📦 Vips output: #{file_size} bytes"
    
    temp_file
  end

  def validate_processed_file
    return unless @processed_file

    file_size = @processed_file.size
    if file_size > MAX_OUTPUT_SIZE
      # Try with lower quality if file is too large
      @processed_file = reprocess_with_lower_quality
      file_size = @processed_file.size

      if file_size > MAX_OUTPUT_SIZE
        errors.add(:file, "processed file is too large (#{file_size / 1.kilobyte}KB). WhatsApp stickers must be under #{MAX_OUTPUT_SIZE / 1.kilobyte}KB")
      end
    end
  end

  def reprocess_with_lower_quality
    # Retry with lower quality settings
    processed = ImageProcessing::Vips
      .source(file)
      .resize_to_fill(STICKER_DIMENSIONS, STICKER_DIMENSIONS, crop: :centre)
      .convert('webp')
      .saver(quality: 60, effort: 6) # Lower quality for smaller file size
      .call

    temp_file = Tempfile.new(['processed_sticker_low_quality', '.webp'])
    temp_file.binmode
    temp_file.write(processed.read)
    temp_file.rewind
    temp_file
  end
end