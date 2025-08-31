# StickerUploader handles image processing for custom stickers
# Converts images to WebP format with 512x512 dimensions and validates file size
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
    # Use ImageProcessing with Vips for better performance and WebP support
    processed = ImageProcessing::Vips
      .source(file)
      .resize_to_fill(STICKER_DIMENSIONS, STICKER_DIMENSIONS, crop: :centre)
      .convert('webp')
      .saver(quality: 85, effort: 6) # Good quality with reasonable compression
      .call

    # Create a temporary file with the processed image
    temp_file = Tempfile.new(['processed_sticker', '.webp'])
    temp_file.binmode
    temp_file.write(processed.read)
    temp_file.rewind
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