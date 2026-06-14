require 'rails_helper'
require 'vips'

RSpec.describe Stickers::ConverterService do
  let(:account) { create(:account) }
  let(:user) { create(:user) }

  # 600x400 red RGB PNG generated with libvips (no fixture file needed)
  def png_bytes(width = 600, height = 400)
    Vips::Image.black(width, height).add([255, 0, 0]).cast(:uchar)
               .copy(interpretation: :srgb).write_to_buffer('.png')
  end

  # Wraps raw bytes as an uploaded file for the service
  def upload(bytes, content_type = 'image/png')
    file = Tempfile.new(['src', ".#{content_type.split('/').last}"])
    file.binmode
    file.write(bytes)
    file.rewind
    ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: 'src', type: content_type)
  end

  describe 'static image' do
    # WhatsApp rejects artificially-alpha'd webp as stickers, so the converter
    # center-crops to 512x512 and saves a plain webp (no forced transparent padding).
    it 'produces a 512x512 webp under 100KB', :aggregate_failures do
      sticker = described_class.new(account: account, user: user, file: upload(png_bytes)).perform

      expect(sticker).to be_persisted
      expect(sticker.animated).to be(false)
      expect(sticker.file).to be_attached
      expect(sticker.file.content_type).to eq('image/webp')

      out = Vips::Image.new_from_buffer(sticker.file.download, '')
      expect(out.width).to eq(512)
      expect(out.height).to eq(512)
      expect(sticker.file.byte_size).to be <= 100.kilobytes
    end
  end

  describe 'animated image' do
    # 3-frame animated gif via libvips (vertical toilet-roll + page-height/n-pages).
    # Frames must differ; webp encoders collapse identical consecutive frames.
    def animated_gif_bytes
      colors = [[255, 0, 0], [0, 255, 0], [0, 0, 255]]
      frames = colors.map { |c| Vips::Image.black(120, 120).add(c).cast(:uchar).copy(interpretation: :srgb) }
      strip = Vips::Image.arrayjoin(frames, across: 1)
      strip = strip.copy
      strip.set_type(GObject::GINT_TYPE, 'page-height', 120)
      strip.set_type(GObject::GINT_TYPE, 'n-pages', 3)
      strip.write_to_buffer('.gif')
    end

    it 'produces an animated webp under 500KB preserving multiple frames', :aggregate_failures do
      sticker = described_class.new(account: account, user: user, file: upload(animated_gif_bytes, 'image/gif')).perform

      expect(sticker.animated).to be(true)
      expect(sticker.file.content_type).to eq('image/webp')
      out = Vips::Image.new_from_buffer(sticker.file.download, '', n: -1)
      expect(out.get('n-pages')).to be > 1
      expect(sticker.file.byte_size).to be <= 500.kilobytes
    end
  end
end
