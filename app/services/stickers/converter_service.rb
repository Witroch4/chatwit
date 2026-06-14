require 'vips'

class Stickers::ConverterService
  TARGET = 512
  MAX_INPUT_BYTES = 5.megabytes
  STATIC_MAX_BYTES = 100.kilobytes
  ANIMATED_MAX_BYTES = 500.kilobytes
  QUALITY_STEPS = [80, 70, 60, 50, 40, 30].freeze

  class InvalidSource < StandardError; end

  def initialize(account:, user:, file: nil, blob: nil)
    @account = account
    @user = user
    @bytes = read_bytes(file, blob)
  end

  def perform
    raise InvalidSource, 'empty source' if @bytes.blank?
    raise InvalidSource, 'source too large' if @bytes.bytesize > MAX_INPUT_BYTES

    webp, animated = build_webp
    sticker = @account.stickers.new(user: @user, animated: animated)
    sticker.file.attach(io: StringIO.new(webp), filename: 'sticker.webp', content_type: 'image/webp')
    sticker.save!
    sticker
  end

  private

  def read_bytes(file, blob)
    return file.read if file.respond_to?(:read)
    return blob.download if blob

    nil
  end

  def build_webp
    if page_count > 1
      [optimize_animated, true]
    else
      [optimize_static, false]
    end
  rescue Vips::Error => e
    raise InvalidSource, e.message
  end

  def page_count
    Vips::Image.new_from_buffer(@bytes, '', access: :sequential, n: -1).get('n-pages')
  rescue Vips::Error
    1
  end

  def optimize_static
    image = Vips::Image.thumbnail_buffer(@bytes, TARGET, height: TARGET, size: :down)
    image = ensure_rgba(image)
    square = image.gravity('centre', TARGET, TARGET, extend: :background, background: [0, 0, 0, 0])
    encode_within(square, STATIC_MAX_BYTES)
  end

  # Normalizes any colourspace to 4-band RGBA so padding can be transparent.
  def ensure_rgba(image)
    image = image.colourspace(:srgb) if image.bands < 3
    image = image.bandjoin(255) if image.bands == 3
    image
  end

  def encode_within(image, max_bytes)
    QUALITY_STEPS.each do |q|
      bytes = image.write_to_buffer('.webp', Q: q, effort: 4)
      return bytes if bytes.bytesize <= max_bytes
    end
    image.write_to_buffer('.webp', Q: QUALITY_STEPS.last, effort: 4)
  end
end
