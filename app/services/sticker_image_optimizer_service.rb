# frozen_string_literal: true

require 'mini_magick'
require 'benchmark'

class StickerImageOptimizerService
  include ActiveModel::Model
  include ActiveModel::Attributes

  # WhatsApp sticker size limits
  MAX_STATIC_FILE_SIZE = 100.kilobytes
  MAX_ANIMATED_FILE_SIZE = 500.kilobytes
  TARGET_DIMENSIONS = [512, 512].freeze
  SUPPORTED_FORMATS = %w[image/jpeg image/png image/gif image/webp].freeze
  OUTPUT_FORMAT = 'webp'
  QUALITY_LEVELS = [95, 85, 75, 65, 55].freeze

  attr_accessor :file, :account_id

  def initialize(file:, account_id: nil)
    @file = file
    @account_id = account_id
    @metrics_service = StickerPerformanceMetricsService.instance
  end

  def process
    start_time = Time.current
    
    begin
      validate_input!
      
      # Track processing start
      Rails.logger.info "Starting sticker image optimization for account #{@account_id}"
      
      result = optimize_image
      
      # Track successful processing
      processing_time = (Time.current - start_time) * 1000 # Convert to milliseconds
      @metrics_service.track_api_performance(
        api_name: 'image_processing',
        response_time: processing_time,
        success: true
      )
      
      Rails.logger.info "Sticker image optimization completed in #{processing_time.round(2)}ms"
      
      {
        success: true,
        processed_file: result[:processed_file],
        original_size: result[:original_size],
        final_size: result[:final_size],
        compression_ratio: result[:compression_ratio],
        processing_time: processing_time.round(2),
        is_animated: result[:is_animated],
        has_transparency: result[:has_transparency]
      }
      
    rescue StandardError => e
      # Track failed processing
      processing_time = (Time.current - start_time) * 1000
      @metrics_service.track_api_performance(
        api_name: 'image_processing',
        response_time: processing_time,
        success: false
      )
      
      Rails.logger.error "Sticker image optimization failed: #{e.message}"
      
      {
        success: false,
        error: e.message,
        processing_time: processing_time.round(2)
      }
    end
  end

  # Method specifically for WhatsApp sticker optimization (public method)
  def optimize_for_whatsapp(input_path)
    Rails.logger.info "StickerImageOptimizerService: Optimizing for WhatsApp: #{input_path}"
    
    # Create output path
    output_path = input_path.gsub(/\.[^.]+$/, '_optimized.webp')
    
    begin
      # Load image
      image = MiniMagick::Image.open(input_path)
      
      # Detect animation and transparency
      is_animated = animated?(image)
      has_transparency = has_transparency?(image)
      
      Rails.logger.info "StickerImageOptimizerService: WhatsApp optimization - animated: #{is_animated}, transparent: #{has_transparency}"
      
      # WhatsApp sticker requirements:
      # - WebP format
      # - Max 512x512 pixels
      # - Max 100KB for static, 500KB for animated
      # - Square aspect ratio preferred
      # - Preserve animation and transparency
      
      max_file_size = is_animated ? MAX_ANIMATED_FILE_SIZE : MAX_STATIC_FILE_SIZE
      
      # Start with high quality and reduce if needed
      QUALITY_LEVELS.each do |quality|
        # Create a copy for processing
        working_image = image.dup
        
        # Apply optimization with preservation
        optimized_image = process_image_with_quality_and_preservation(working_image, quality, is_animated, has_transparency)
        
        # Write temporary file to check size
        temp_output = "#{output_path}.tmp"
        optimized_image.write(temp_output)
        
        file_size = File.size(temp_output)
        
        if file_size <= max_file_size
          File.rename(temp_output, output_path)
          Rails.logger.info "StickerImageOptimizerService: Optimized to #{file_size} bytes at quality #{quality} (limit: #{max_file_size})"
          return output_path
        else
          File.delete(temp_output) if File.exist?(temp_output)
        end
      end
      
      # If still too large, use lowest quality with preservation
      working_image = image.dup
      optimized_image = process_image_with_quality_and_preservation(working_image, QUALITY_LEVELS.last, is_animated, has_transparency)
      optimized_image.write(output_path)
      
      final_size = File.size(output_path)
      Rails.logger.warn "StickerImageOptimizerService: Using lowest quality, final size: #{final_size} bytes (limit: #{max_file_size})"
      output_path
      
    rescue StandardError => e
      Rails.logger.error "StickerImageOptimizerService: Optimization failed: #{e.message}"
      # Clean up any temporary files
      [output_path, "#{output_path}.tmp"].each do |path|
        File.delete(path) if File.exist?(path)
      end
      raise e
    end
  end

  private

  def validate_input!
    raise ArgumentError, 'File is required' unless @file
    raise ArgumentError, 'File must respond to read' unless @file.respond_to?(:read)
    
    # Check file size
    file_size = @file.size
    raise ArgumentError, 'File is too large (max 5MB for processing)' if file_size > 5.megabytes
    
    # Check content type if available
    if @file.respond_to?(:content_type) && @file.content_type
      unless SUPPORTED_FORMATS.include?(@file.content_type)
        raise ArgumentError, "Unsupported file format: #{@file.content_type}"
      end
    end
  end

  def optimize_image
    original_size = @file.size
    
    # Create temporary file for processing
    temp_file = Tempfile.new(['sticker_processing', '.webp'])
    
    begin
      # Read file content
      file_content = @file.read
      @file.rewind if @file.respond_to?(:rewind)
      
      # Process with MiniMagick for optimal performance
      image = MiniMagick::Image.read(file_content)
      
      # Validate image
      validate_image!(image)
      
      # Detect animation and transparency
      is_animated = animated?(image)
      has_transparency = has_transparency?(image)
      
      Rails.logger.info "StickerImageOptimizer: Processing sticker - animated: #{is_animated}, transparent: #{has_transparency}"
      
      # Optimize image preserving animation and transparency
      optimized_image = optimize_with_preservation(image, is_animated, has_transparency)
      
      # Write to temporary file
      optimized_image.write(temp_file.path)
      
      final_size = File.size(temp_file.path)
      compression_ratio = ((original_size - final_size).to_f / original_size * 100).round(2)
      
      # Create ActionDispatch::Http::UploadedFile compatible object
      processed_file = ActionDispatch::Http::UploadedFile.new(
        tempfile: temp_file,
        filename: generate_filename(is_animated),
        type: 'image/webp',
        head: "Content-Disposition: form-data; name=\"file\"; filename=\"#{generate_filename(is_animated)}\"\r\nContent-Type: image/webp\r\n"
      )
      
      {
        processed_file: processed_file,
        original_size: original_size,
        final_size: final_size,
        compression_ratio: compression_ratio,
        is_animated: is_animated,
        has_transparency: has_transparency
      }
      
    rescue StandardError => e
      temp_file.close! if temp_file
      raise e
    end
  end

  def validate_image!(image)
    # Check if it's a valid image
    raise ArgumentError, 'Invalid image file' unless image.valid?
    
    # Check dimensions (allow larger images, we'll resize them)
    width = image.width
    height = image.height
    
    raise ArgumentError, 'Image dimensions too small (minimum 64x64)' if width < 64 || height < 64
    raise ArgumentError, 'Image dimensions too large (maximum 2048x2048)' if width > 2048 || height > 2048
  end

  # Detect if image is animated (has multiple frames)
  def animated?(image)
    image.frames.count > 1
  rescue StandardError => e
    Rails.logger.debug "StickerImageOptimizer: Error detecting animation: #{e.message}"
    false
  end

  # Detect if image has transparency (alpha channel)
  def has_transparency?(image)
    # Check if image has alpha channel using identify command
    result = image.identify do |b|
      b.format '%A'
    end
    result.strip.downcase == 'true'
  rescue StandardError => e
    Rails.logger.debug "StickerImageOptimizer: Error detecting transparency: #{e.message}"
    # Fallback: check if format typically supports transparency
    %w[png gif webp].include?(image.type.downcase)
  end

  # Optimize preserving animation and transparency
  def optimize_with_preservation(image, is_animated, has_transparency)
    max_file_size = is_animated ? MAX_ANIMATED_FILE_SIZE : MAX_STATIC_FILE_SIZE
    
    Rails.logger.info "StickerImageOptimizer: Using #{is_animated ? 'animated' : 'static'} size limit: #{max_file_size} bytes"
    
    # Start with highest quality and reduce until file size is acceptable
    QUALITY_LEVELS.each do |quality|
      optimized = process_image_with_quality_and_preservation(image.dup, quality, is_animated, has_transparency)
      
      # Check file size by writing to a temporary location
      temp_check = Tempfile.new(['size_check', '.webp'])
      begin
        optimized.write(temp_check.path)
        file_size = File.size(temp_check.path)
        
        if file_size <= max_file_size
          Rails.logger.debug "Sticker optimized at quality #{quality}, size: #{file_size} bytes"
          return optimized
        end
      ensure
        temp_check.close!
      end
    end
    
    # If we can't get under the size limit, use the lowest quality
    Rails.logger.warn "Sticker optimization: using lowest quality, may exceed size limit"
    process_image_with_quality_and_preservation(image, QUALITY_LEVELS.last, is_animated, has_transparency)
  end

  def optimize_with_quality_levels(image)
    # Legacy method - redirect to new preservation method
    is_animated = animated?(image)
    has_transparency = has_transparency?(image)
    optimize_with_preservation(image, is_animated, has_transparency)
  end

  def process_image_with_quality_and_preservation(image, quality, is_animated, has_transparency)
    # Resize to target dimensions maintaining aspect ratio
    image.resize "#{TARGET_DIMENSIONS[0]}x#{TARGET_DIMENSIONS[1]}^"
    image.gravity 'center'
    image.extent "#{TARGET_DIMENSIONS[0]}x#{TARGET_DIMENSIONS[1]}"
    
    # Convert to WebP with specified quality
    image.format OUTPUT_FORMAT
    image.quality quality
    
    # Preserve animation for animated stickers
    if is_animated
      Rails.logger.debug "StickerImageOptimizer: Preserving animation with WebP animated format"
      # Keep all frames for animation
      image.define 'webp:method=6' # Best compression for animated WebP
      image.define 'webp:minimize-size=1' # Minimize file size
      # Don't strip metadata for animated images as it may break animation
    else
      # Static image optimizations
      image.strip # Remove metadata for static images
      image.interlace 'none' # Disable interlacing for smaller file size
      image.define 'webp:method=6' # Highest compression method
    end
    
    # Preserve transparency
    if has_transparency
      Rails.logger.debug "StickerImageOptimizer: Preserving transparency with alpha channel"
      # Ensure alpha channel is preserved
      begin
        image.alpha 'set' # Ensure alpha channel exists
      rescue StandardError => e
        Rails.logger.debug "StickerImageOptimizer: Could not set alpha channel: #{e.message}"
      end
      image.define 'webp:alpha-compression=1' # Enable alpha compression
      image.define 'webp:alpha-filtering=2' # Best alpha filtering
      image.define 'webp:alpha-quality=100' # Preserve alpha quality
      # Don't add background color to preserve transparency
    else
      # For non-transparent images, we can optimize alpha channel away
      begin
        # Check if image has alpha before trying to remove it
        alpha_info = image.identify { |b| b.format '%A' }
        if alpha_info.strip.downcase == 'true'
          image.alpha 'remove'
        end
      rescue StandardError => e
        Rails.logger.debug "StickerImageOptimizer: Could not remove alpha channel: #{e.message}"
      end
    end
    
    # Set target size based on animation status
    max_size = is_animated ? MAX_ANIMATED_FILE_SIZE : MAX_STATIC_FILE_SIZE
    image.define 'webp:target-size=' + max_size.to_s if quality < 75
    
    image
  end

  def process_image_with_quality(image, quality)
    # Legacy method - redirect to new preservation method
    is_animated = animated?(image)
    has_transparency = has_transparency?(image)
    process_image_with_quality_and_preservation(image, quality, is_animated, has_transparency)
  end

  def generate_filename(is_animated = false)
    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    random_suffix = SecureRandom.hex(4)
    animation_suffix = is_animated ? '_animated' : ''
    "sticker_#{timestamp}_#{random_suffix}#{animation_suffix}.webp"
  end

  # Class method for batch processing
  def self.batch_process(files, account_id: nil)
    results = []
    total_start_time = Time.current
    
    files.each_with_index do |file, index|
      Rails.logger.info "Processing sticker #{index + 1}/#{files.length}"
      
      service = new(file: file, account_id: account_id)
      result = service.process
      
      results << result.merge(file_index: index)
    end
    
    total_processing_time = (Time.current - total_start_time) * 1000
    
    {
      results: results,
      total_files: files.length,
      successful: results.count { |r| r[:success] },
      failed: results.count { |r| !r[:success] },
      total_processing_time: total_processing_time.round(2)
    }
  end

  # Performance benchmark method
  def self.benchmark_processing(file, iterations: 5)
    results = []
    
    iterations.times do |i|
      Rails.logger.info "Benchmark iteration #{i + 1}/#{iterations}"
      
      service = new(file: file)
      result = service.process
      
      results << {
        iteration: i + 1,
        success: result[:success],
        processing_time: result[:processing_time],
        final_size: result[:final_size],
        compression_ratio: result[:compression_ratio]
      }
    end
    
    successful_results = results.select { |r| r[:success] }
    
    if successful_results.any?
      processing_times = successful_results.map { |r| r[:processing_time] }
      
      {
        iterations: iterations,
        successful: successful_results.length,
        failed: results.length - successful_results.length,
        avg_processing_time: (processing_times.sum / processing_times.length).round(2),
        min_processing_time: processing_times.min.round(2),
        max_processing_time: processing_times.max.round(2),
        avg_compression_ratio: (successful_results.map { |r| r[:compression_ratio] }.sum / successful_results.length).round(2)
      }
    else
      {
        iterations: iterations,
        successful: 0,
        failed: results.length,
        error: 'All iterations failed'
      }
    end
  end
end