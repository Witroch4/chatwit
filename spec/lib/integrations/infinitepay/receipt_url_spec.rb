# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Infinitepay::ReceiptUrl do
  it 'keeps only https links on the official InfinitePay receipt host' do
    expect(described_class.safe('https://recibo.infinitepay.io/abc?x=1')).to eq('https://recibo.infinitepay.io/abc?x=1')
    expect(described_class.safe(' https://recibo.infinitepay.io/abc ')).to eq('https://recibo.infinitepay.io/abc')
  end

  it 'drops anything else' do
    [
      'http://recibo.infinitepay.io/abc',
      'https://recibo.infinitepay.io.evil.com/abc',
      'https://evil.com/recibo.infinitepay.io/abc',
      'javascript:alert(1)',
      'not a url',
      '',
      nil
    ].each { |url| expect(described_class.safe(url)).to be_nil, "expected #{url.inspect} to be dropped" }
  end
end
