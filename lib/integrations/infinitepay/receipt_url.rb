# frozen_string_literal: true

# The InfinitePay webhook is not signed, so its receipt link is untrusted input.
# Only https links on the official receipt host are kept; anything else is
# dropped before it is stored, sent to the lead or forwarded to the Platform
# (which applies the same rule on its side).
module Integrations::Infinitepay::ReceiptUrl
  HOST = 'recibo.infinitepay.io'

  def self.safe(url)
    uri = URI.parse(url.to_s.strip)
    uri.is_a?(URI::HTTPS) && uri.host == HOST ? uri.to_s : nil
  rescue URI::InvalidURIError
    nil
  end
end
