require 'vips'

class Stickers::ConverterService
  TARGET = 512
  MAX_INPUT_BYTES = 5.megabytes
  STATIC_MAX_BYTES = 100.kilobytes
  ANIMATED_MAX_BYTES = 500.kilobytes
  QUALITY_STEPS = [85, 75, 65, 55, 45, 35].freeze
  WEBP_EFFORT = 6

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

  # Matches the proven WhatsApp-accepted recipe: center-crop to 512x512 and save
  # a plain webp. We intentionally do NOT add an alpha channel / transparent
  # padding here — WhatsApp rejects such artificially-alpha'd webp as stickers
  # ("Sticker file could not be processed", error 131053). Source transparency
  # (e.g. a received sticker) is preserved as-is.
  def optimize_static
    image = Vips::Image.thumbnail_buffer(@bytes, TARGET, height: TARGET, crop: :centre)
    encode_within(image, STATIC_MAX_BYTES)
  end

  def optimize_animated
    # libvips thumbnail is animation-aware when the loader reads all pages via
    # the 'n=-1' option string. The result keeps the page/animation metadata,
    # and webpsave then writes an animated webp.
    thumb = Vips::Image.thumbnail_buffer(@bytes, TARGET, height: TARGET, size: :down, option_string: 'n=-1')
    encode_within(thumb, ANIMATED_MAX_BYTES)
  rescue Vips::Error
    # Fallback: first frame as a static sticker (still valid for WhatsApp).
    optimize_static
  end

  # strip: true removes ICC/EXIF metadata so opaque stickers serialize as a plain
  # webp (not the extended VP8X container), which WhatsApp accepts cleanly.
  def encode_within(image, max_bytes)
    QUALITY_STEPS.each do |q|
      bytes = image.write_to_buffer('.webp', Q: q, effort: WEBP_EFFORT, strip: true)
      return bytes if bytes.bytesize <= max_bytes
    end
    image.write_to_buffer('.webp', Q: QUALITY_STEPS.last, effort: WEBP_EFFORT, strip: true)
  end
end
