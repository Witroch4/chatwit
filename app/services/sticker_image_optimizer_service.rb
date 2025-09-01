# frozen_string_literal: true

require 'mini_magick'
require 'benchmark'

class StickerImageOptimizerService
  include ActiveModel::Model
  include ActiveModel::Attributes

  # WhatsApp sticker size limits
  MAX_STATIC_FILE_SIZE = 100.kilobytes
  MAX_ANIMATED_FILE_SIZE = 500.kilobytes
  TARGET_DIMENSIONS = [512, 512].freeze # CORRIGIDO: Valor inicializado
  SUPPORTED_FORMATS = %w[image/jpeg image/png image/gif image/webp].freeze
  OUTPUT_FORMAT = 'webp'
  QUALITY_LEVELS = [85, 75, 65, 55, 45].freeze # CORRIGIDO: Valor inicializado

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

      Rails.logger.info "Starting sticker image optimization for account #{@account_id}"

      result = optimize_image

      processing_time = (Time.current - start_time) * 1000
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

  def optimize_for_whatsapp(input_path)
    Rails.logger.info "StickerImageOptimizerService: Optimizing for WhatsApp: #{input_path}"
    output_path = input_path.gsub(/\.[^.]+$/, '_optimized.webp')

    begin
      image = MiniMagick::Image.open(input_path)
      is_animated = animated?(image)
      has_transparency = has_transparency?(image)

      Rails.logger.info "StickerImageOptimizerService: WhatsApp optimization - animated: #{is_animated}, transparent: #{has_transparency}"

      # CORRIGIDO: Chamada de método e operador ternário
      max_file_size = is_animated ? MAX_ANIMATED_FILE_SIZE : MAX_STATIC_FILE_SIZE

      QUALITY_LEVELS.each do |quality|
        working_image = image.dup
        optimized_image = process_image_with_quality_and_preservation(working_image, quality, is_animated, has_transparency)

        temp_output = "#{output_path}.tmp"
        optimized_image.write(temp_output)
        file_size = File.size(temp_output)

        if file_size <= max_file_size
          temp_check_image = MiniMagick::Image.open(temp_output)
          temp_width = temp_check_image.width
          temp_height = temp_check_image.height

          Rails.logger.info "📐 Dimensions at quality #{quality}: #{temp_width}x#{temp_height}"

          # CORRIGIDO: Operador lógico
          if temp_width != TARGET_DIMENSIONS[0] || temp_height != TARGET_DIMENSIONS[1]
            Rails.logger.error "❌ Wrong dimensions at quality #{quality}: #{temp_width}x#{temp_height}, expected #{TARGET_DIMENSIONS[0]}x#{TARGET_DIMENSIONS[1]}"
            File.delete(temp_output) if File.exist?(temp_output)
            next
          end

          File.rename(temp_output, output_path)
          Rails.logger.info "StickerImageOptimizerService: Optimized to #{file_size} bytes at quality #{quality} (limit: #{max_file_size})"
          Rails.logger.info "✅ Dimensions verified: #{temp_width}x#{temp_height}"
          return output_path
        else
          File.delete(temp_output) if File.exist?(temp_output)
        end
      end

      working_image = image.dup
      optimized_image = process_image_with_quality_and_preservation(working_image, QUALITY_LEVELS.last, is_animated, has_transparency)
      optimized_image.write(output_path)
      final_size = File.size(output_path)
      Rails.logger.warn "StickerImageOptimizerService: Using lowest quality, final size: #{final_size} bytes (limit: #{max_file_size})"

      final_check_image = MiniMagick::Image.open(output_path)
      final_width = final_check_image.width
      final_height = final_check_image.height
      Rails.logger.info "📐 [FINAL_CHECK] WhatsApp output dimensions: #{final_width}x#{final_height}"

      # CORRIGIDO: Operador lógico
      if final_width != TARGET_DIMENSIONS[0] || final_height != TARGET_DIMENSIONS[1]
        error_msg = "Final dimension check failed: got #{final_width}x#{final_height}, expected #{TARGET_DIMENSIONS[0]}x#{TARGET_DIMENSIONS[1]}"
        Rails.logger.error "❌ [FINAL_CHECK] CRITICAL: #{error_msg}"
        raise error_msg
      end

      output_path

    rescue StandardError => e
      Rails.logger.error "StickerImageOptimizerService: Optimization failed: #{e.message}"
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

    file_size = @file.size
    raise ArgumentError, 'File is too large (max 5MB for processing)' if file_size > 5.megabytes

    if @file.respond_to?(:content_type) && @file.content_type
      raise ArgumentError, "Unsupported file format: #{@file.content_type}" unless SUPPORTED_FORMATS.include?(@file.content_type)
    end
  end

  def optimize_image
    original_size = @file.size
    temp_file = Tempfile.new(['sticker_processing', '.webp'])

    begin
      file_content = @file.read
      @file.rewind if @file.respond_to?(:rewind)
      image = MiniMagick::Image.read(file_content)
      validate_image!(image)

      is_animated = animated?(image)
      has_transparency = has_transparency?(image)
      Rails.logger.info "🔍 StickerImageOptimizer: Processing sticker - animated: #{is_animated}, transparent: #{has_transparency}"

      optimized_image = optimize_with_preservation(image, is_animated, has_transparency)

      final_frame_count = MiniMagick::Image.open(optimized_image.path).frames.count
      # CORRIGIDO: Operador ternário e nome do método
      log_animated_status = is_animated ? 'animated' : 'static'
      log_frame_expectation = is_animated ? '> 1' : '1'
      Rails.logger.info "🎬 FINAL RESULT: #{final_frame_count} frames (should be #{log_frame_expectation} for #{log_animated_status})"

      optimized_image.write(temp_file.path)
      final_size = File.size(temp_file.path)
      compression_ratio = ((original_size - final_size).to_f / original_size * 100).round(2)

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
    raise ArgumentError, 'Invalid image file' unless image.valid?

    width = image.width
    height = image.height

    # CORRIGIDO: Operador lógico
    raise ArgumentError, 'Image dimensions too small (minimum 64x64)' if width < 64 || height < 64
    raise ArgumentError, 'Image dimensions too large (maximum 2048x2048)' if width > 2048 || height > 2048
  end

  def animated?(image)
    frame_count = image.frames.count
    Rails.logger.info "🎬 Original image has #{frame_count} frames"
    frame_count > 1
  rescue StandardError => e
    Rails.logger.debug "StickerImageOptimizer: Error detecting animation: #{e.message}"
    false
  end

  def has_transparency?(image)
    result = image.identify do |b|
      b.format '%A'
    end
    result.strip.downcase == 'true'
  rescue StandardError => e
    Rails.logger.debug "StickerImageOptimizer: Error detecting transparency: #{e.message}"
    %w[png gif webp].include?(image.type.downcase)
  end

  def optimize_with_preservation(image, is_animated, has_transparency)
    original_frames = image.frames.count
    # CORRIGIDO: Chamada de método e operador ternário
    max_file_size = is_animated ? MAX_ANIMATED_FILE_SIZE : MAX_STATIC_FILE_SIZE

    Rails.logger.info "🎯 StickerImageOptimizer: Using #{is_animated ? 'animated' : 'static'} size limit: #{max_file_size} bytes (original frames: #{original_frames})"

    QUALITY_LEVELS.each do |quality|
      optimized = process_image_with_quality_and_preservation(image.dup, quality, is_animated, has_transparency)
      temp_check = Tempfile.new(['size_check', '.webp'])
      begin
        optimized.write(temp_check.path)
        file_size = File.size(temp_check.path)
        frames_after_write = MiniMagick::Image.open(temp_check.path).frames.count

        Rails.logger.info "🎬 Quality #{quality}: #{frames_after_write} frames, #{file_size} bytes"

        if file_size <= max_file_size
          Rails.logger.info "✅ Sticker optimized at quality #{quality}, size: #{file_size} bytes, frames: #{frames_after_write}"
          return optimized
        end
      ensure
        temp_check.close!
      end
    end

    Rails.logger.warn "⚠️ Sticker optimization: using lowest quality, may exceed size limit"
    final_optimized = process_image_with_quality_and_preservation(image, QUALITY_LEVELS.last, is_animated, has_transparency)
    final_frames = MiniMagick::Image.open(final_optimized.path).frames.count
    Rails.logger.warn "🎬 Final fallback: #{final_frames} frames"
    final_optimized
  end

  def process_image_with_quality_and_preservation(image, quality, is_animated, has_transparency)
    Rails.logger.info "🎬 [FRAMES] Starting process_image - animated: #{is_animated}, quality: #{quality}"

    # Log dimensões originais
    original_width = image.width
    original_height = image.height
    Rails.logger.info "📐 [DIMENSIONS] Input: #{original_width}x#{original_height}"

    if is_animated
      # CORREÇÃO CRÍTICA: Para WebP animado, precisamos usar magick (não convert)
      # e aplicar os comandos de forma específica para preservar todos os frames
      Rails.logger.info "🎬 [ANIMATED] Processing animated WebP with frame preservation"

      # Criar arquivos temporários
      temp_input = Tempfile.new(['animated_input', File.extname(image.path)])
      temp_output = Tempfile.new(['animated_output', '.webp'])

      begin
        # Salvar imagem original
        image.write(temp_input.path)

        # Verificar número de frames antes do processamento
        original_frame_count = `identify -format "%n\\n" "#{temp_input.path}" | head -1`.strip.to_i
        Rails.logger.info "🎬 [FRAMES] Original file has #{original_frame_count} frames"

        # IMPORTANTE: Usar magick (não convert) para melhor suporte a WebP animado
        # e processar TODOS os frames de uma vez com colchetes [0--1]
        command = [
          'magick',  # Usar magick ao invés de convert
          "#{temp_input.path}[0--1]",  # CRÍTICO: Processar TODOS os frames (0 até o último)
          '-coalesce',  # Descompacta frames para processamento individual
          '-background', 'transparent',  # Background transparente
          '-alpha', 'set',  # Ativa canal alpha
          '-resize', "#{TARGET_DIMENSIONS[0]}x#{TARGET_DIMENSIONS[1]}",  # Resize mantendo proporção
          '-gravity', 'center',  # Centraliza
          '-background', 'transparent',  # Reforça transparência no extent
          '-extent', "#{TARGET_DIMENSIONS[0]}x#{TARGET_DIMENSIONS[1]}",  # Canvas 512x512
          '+repage',  # Remove informações de canvas offset
          '-set', 'dispose', 'background',  # Define método de dispose para frames
          '-loop', '0',  # Loop infinito
          '-quality', quality.to_s,
          '-define', 'webp:method=6',
          '-define', 'webp:lossless=false',
          '-define', 'webp:thread-level=1',  # Melhora processamento de animação
          '-define', 'webp:auto-filter=true',
          '-define', 'webp:alpha-compression=1',
          '-define', 'webp:alpha-quality=100',
          '-define', 'webp:use-sharp-yuv=1',
          'WEBP:' + temp_output.path  # IMPORTANTE: Prefixo WEBP: força formato WebP
        ]

        Rails.logger.info "� [COMMAND] #{command.join(' ')}"

        # Executar comando
        result = `#{command.join(' ')} 2>&1`
        exit_status = $?.exitstatus

        if exit_status == 0
          # Verificar frames no arquivo de saída
          output_frame_count = `identify -format "%n\\n" "#{temp_output.path}" | head -1`.strip.to_i
          Rails.logger.info "✅ [ANIMATED] Processed successfully - Output has #{output_frame_count} frames"

          if output_frame_count != original_frame_count
            Rails.logger.warn "⚠️ [FRAMES] Frame count mismatch: input=#{original_frame_count}, output=#{output_frame_count}"
          end

          # Carregar imagem processada
          image = MiniMagick::Image.open(temp_output.path)
        else
          Rails.logger.error "❌ [ANIMATED] Command failed with exit status #{exit_status}: #{result}"

          # Fallback: tentar com convert se magick falhar
          Rails.logger.info "🔄 [FALLBACK] Trying with convert command..."
          fallback_command = command.dup
          fallback_command[0] = 'convert'

          result = `#{fallback_command.join(' ')} 2>&1`

          if $?.success?
            image = MiniMagick::Image.open(temp_output.path)
            Rails.logger.info "✅ [FALLBACK] Convert command succeeded"
          else
            raise "Failed to process animated image: #{result}"
          end
        end

      ensure
        temp_input.close!
        temp_output.close! if File.exist?(temp_output.path) && image.path != temp_output.path
      end

    else
      # Para imagens estáticas
      Rails.logger.info "🖼️ [STATIC] Processing static image"

      # Usar combine_options para imagem estática
      image.combine_options do |c|
        c.background 'transparent'
        c.alpha 'set'
        c.resize "#{TARGET_DIMENSIONS[0]}x#{TARGET_DIMENSIONS[1]}"
        c.gravity 'center'
        c.background 'transparent'
        c.extent "#{TARGET_DIMENSIONS[0]}x#{TARGET_DIMENSIONS[1]}"
        c.strip  # Remove metadata
        c.quality quality.to_s
        c.define 'webp:method=6'
        c.define 'webp:lossless=false'

        if has_transparency
          c.define 'webp:alpha-compression=1'
          c.define 'webp:alpha-quality=100'
        end
      end
    end

    # Verificação final de dimensões
    final_width = image.width
    final_height = image.height
    Rails.logger.info "📐 [DIMENSIONS] Output: #{final_width}x#{final_height} (target: #{TARGET_DIMENSIONS[0]}x#{TARGET_DIMENSIONS[1]})"

    if final_width != TARGET_DIMENSIONS[0] || final_height != TARGET_DIMENSIONS[1]
      Rails.logger.error "❌ [DIMENSIONS] Output dimensions #{final_width}x#{final_height} do not match target"

      # Tentativa de correção forçada
      Rails.logger.info "🔧 [FIX] Attempting forced resize to exact dimensions..."
      image.combine_options do |c|
        c.resize "#{TARGET_DIMENSIONS[0]}x#{TARGET_DIMENSIONS[1]}!"  # ! força dimensões exatas
        c.background 'transparent'
        c.extent "#{TARGET_DIMENSIONS[0]}x#{TARGET_DIMENSIONS[1]}"
      end

      # Verificar novamente
      final_width = image.width
      final_height = image.height

      if final_width != TARGET_DIMENSIONS[0] || final_height != TARGET_DIMENSIONS[1]
        raise "Dimension optimization failed: got #{final_width}x#{final_height}"
      end
    end

    Rails.logger.info "✅ [DIMENSIONS] SUCCESS: Output matches target 512x512"

    # Log informações de transparência
    if has_transparency || is_animated
      begin
        alpha_info = image.identify { |b| b.format '%A' }
        Rails.logger.info "🎨 [ALPHA] Alpha channel: #{alpha_info.strip}"
      rescue => e
        Rails.logger.warn "⚠️ [ALPHA] Could not check alpha channel: #{e.message}"
      end
    end

    image
  end

  def generate_filename(is_animated = false)
    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    random_suffix = SecureRandom.hex(4)
    # CORRIGIDO: Operador ternário
    animation_suffix = is_animated ? '_animated' : ''
    "sticker_#{timestamp}_#{random_suffix}#{animation_suffix}.webp"
  end

  def self.batch_process(files, account_id: nil)
    results = [] # CORRIGIDO: Inicialização de array
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

  def self.benchmark_processing(file, iterations: 5)
    results = [] # CORRIGIDO: Inicialização de array

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

  # Método auxiliar para debug de frames
  def debug_frame_info(file_path, label = "FILE")
    begin
      # Contar frames
      frame_count = `identify -format "%n\\n" "#{file_path}" | head -1`.strip.to_i

      # Obter informações detalhadas
      info = `identify -verbose "#{file_path}[0]" 2>&1 | head -50`

      # Verificar se é animado
      is_animated = frame_count > 1

      # Verificar formato
      format = `identify -format "%m" "#{file_path}[0]"`.strip

      Rails.logger.info "🔍 [#{label}] Frames: #{frame_count}, Format: #{format}, Animated: #{is_animated}"

      # Se for animado, verificar delay entre frames
      if is_animated
        delays = `identify -format "%T\\n" "#{file_path}"`.strip.split("\n")
        Rails.logger.info "🔍 [#{label}] Frame delays: #{delays.join(', ')}"
      end

      frame_count
    rescue => e
      Rails.logger.error "❌ [DEBUG] Error checking #{label}: #{e.message}"
      0
    end
  end

  # Método alternativo usando ffmpeg (se disponível)
  def process_animated_with_ffmpeg(input_path, output_path, quality)
    Rails.logger.info "🎬 [FFMPEG] Attempting animation processing with ffmpeg"

    command = [
      'ffmpeg',
      '-i', input_path,
      '-vf', "scale=#{TARGET_DIMENSIONS[0]}:#{TARGET_DIMENSIONS[1]}:force_original_aspect_ratio=decrease,pad=#{TARGET_DIMENSIONS[0]}:#{TARGET_DIMENSIONS[1]}:(ow-iw)/2:(oh-ih)/2:color=0x00000000",
      '-codec:v', 'libwebp',
      '-lossless', '0',
      '-compression_level', '6',
      '-quality', quality.to_s,
      '-preset', 'default',
      '-loop', '0',
      '-an',
      '-vsync', '0',
      output_path,
      '-y'  # Sobrescrever arquivo de saída
    ]

    result = `#{command.join(' ')} 2>&1`

    if $?.success?
      Rails.logger.info "✅ [FFMPEG] Animation processed successfully"
      true
    else
      Rails.logger.error "❌ [FFMPEG] Processing failed: #{result}"
      false
    end
  end
end