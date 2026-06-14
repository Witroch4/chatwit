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
    it 'produces a 512x512 transparent-padded webp under 100KB', :aggregate_failures do
      sticker = described_class.new(account: account, user: user, file: upload(png_bytes)).perform

      expect(sticker).to be_persisted
      expect(sticker.animated).to be(false)
      expect(sticker.file).to be_attached
      expect(sticker.file.content_type).to eq('image/webp')

      out = Vips::Image.new_from_buffer(sticker.file.download, '')
      expect(out.width).to eq(512)
      expect(out.height).to eq(512)
      expect(out.bands).to eq(4) # RGBA so padding can be transparent

      # 600x400 landscape centered in 512² => top-left corner is transparent padding
      corner_alpha = out.extract_area(0, 0, 1, 1).extract_band(3).avg
      expect(corner_alpha).to eq(0)
      expect(sticker.file.byte_size).to be <= 100.kilobytes
    end
  end
end
