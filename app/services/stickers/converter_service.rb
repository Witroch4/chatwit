require 'vips'

class Stickers::ConverterService
  TARGET = 512
  MAX_INPUT_BYTES = 5.megabytes
  STATIC_MAX_BYTES = 100.kilobytes
  ANIMATED_MAX_BYTES = 500.kilobytes
  QUALITY_STEPS = [85, 75, 65, 55, 45, 35].freeze
  # Animated webp re-encodes every frame on each pass, so a high effort (6) makes a
  # 50-frame sticker take ~48s on prod and blow past the 15s Rack::Timeout. effort 2
  # encodes the same animation in ~0.3s/pass with a negligible size penalty, and the
  # lower starting quality lands under budget in 1-2 passes instead of 4+ (≈5s on prod).
  ANIMATED_QUALITY_STEPS = [65, 50, 40, 30].freeze
  WEBP_EFFORT = 6
  ANIMATED_WEBP_EFFORT = 2

  class InvalidSource < StandardError; end

  def initialize(account: nil, user: nil, file: nil, blob: nil, bytes: nil)
    @account = account
    @user = user
    @bytes = bytes || read_bytes(file, blob)
  end

  def perform
    webp, animated = to_webp
    sticker = @account.stickers.new(user: @user, animated: animated)
    sticker.file.attach(io: StringIO.new(webp), filename: 'sticker.webp', content_type: 'image/webp')
    sticker.save!
    sticker
  end

  # Returns [webp_bytes, animated_bool] without persisting — reusable by the WhatsApp
  # send path to make raw webp attachments compliant before upload.
  def to_webp
    raise InvalidSource, 'empty source' if @bytes.blank?
    raise InvalidSource, 'source too large' if @bytes.bytesize > MAX_INPUT_BYTES

    build_webp
  end

  # True when the source is ALREADY a WhatsApp-ready sticker (webp, exactly 512x512,
  # within the size cap). Reading only the header is cheap, so this lets the caller
  # skip the expensive decode+re-encode entirely for stickers grabbed as-is.
  def compliant?
    return false if @bytes.blank? || @bytes.bytesize > MAX_INPUT_BYTES

    img = Vips::Image.new_from_buffer(@bytes, '', access: :sequential, n: -1)
    webp_sticker_ready?(img)
  rescue Vips::Error
    false
  end

  private

  def webp_sticker_ready?(img)
    return false unless img.get('vips-loader').to_s.include?('webp')

    animated = field(img, 'n-pages', 1) > 1
    frame_height = animated ? field(img, 'page-height', img.height) : img.height
    limit = animated ? ANIMATED_MAX_BYTES : STATIC_MAX_BYTES
    img.width == TARGET && frame_height == TARGET && @bytes.bytesize <= limit
  end

  # vips raises if a header field is absent (e.g. n-pages on a static webp); fall back.
  def field(img, name, default)
    img.get_typeof(name).zero? ? default : img.get(name)
  end

  def read_bytes(file, blob)
    return file.read if file.respond_to?(:read)
    return blob.download if blob

    nil
  end

  def build_webp
    pages = page_count
    return [@bytes, pages > 1] if compliant?

    if pages > 1
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
    encode_within(image, STATIC_MAX_BYTES, QUALITY_STEPS, WEBP_EFFORT)
  end

  def optimize_animated
    # libvips thumbnail is animation-aware when the loader reads all pages via
    # the 'n=-1' option string. The result keeps the page/animation metadata,
    # and webpsave then writes an animated webp. (crop:centre is NOT usable here —
    # it collapses the frame strip into a single frame.)
    thumb = Vips::Image.thumbnail_buffer(@bytes, TARGET, height: TARGET, size: :down, option_string: 'n=-1')
    bytes = encode_within(thumb, ANIMATED_MAX_BYTES, ANIMATED_QUALITY_STEPS, ANIMATED_WEBP_EFFORT)
    # Guarantee a sendable sticker: if even the lowest quality stays over budget,
    # degrade to the first frame as a static sticker rather than ship a 131053 reject.
    bytes.bytesize <= ANIMATED_MAX_BYTES ? bytes : optimize_static
  rescue Vips::Error
    # Fallback: first frame as a static sticker (still valid for WhatsApp).
    optimize_static
  end

  # strip: true removes ICC/EXIF metadata so opaque stickers serialize as a plain
  # webp (not the extended VP8X container), which WhatsApp accepts cleanly.
  def encode_within(image, max_bytes, steps, effort)
    steps.each do |q|
      bytes = image.write_to_buffer('.webp', Q: q, effort: effort, strip: true)
      return bytes if bytes.bytesize <= max_bytes
    end
    image.write_to_buffer('.webp', Q: steps.last, effort: effort, strip: true)
  end
end
