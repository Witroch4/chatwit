require 'ssrf_filter'

module SafeFetch
  DEFAULT_ALLOWED_CONTENT_TYPE_PREFIXES = %w[image/ video/].freeze
  DEFAULT_ALLOWED_CONTENT_TYPES = [].freeze
  DEFAULT_SENSITIVE_HEADERS = %w[authorization cookie proxy-authorization].freeze
  DEFAULT_OPEN_TIMEOUT = 2
  DEFAULT_READ_TIMEOUT = 20
  DEFAULT_MAX_BYTES_FALLBACK_MB = 40

  Result = Data.define(:tempfile, :filename, :content_type) do
    def original_filename
      filename
    end
  end

  class Error < StandardError; end
  class InvalidUrlError < Error; end
  class UnsafeUrlError < Error; end
  class FetchError < Error; end
  class HttpError < Error; end
  class FileTooLargeError < Error; end
  class UnsupportedContentTypeError < Error; end
  class UnsupportedMethodError < Error; end

  def self.fetch(url, **, &)
    raise ArgumentError, 'block required' unless block_given?

    SafeFetch::Fetcher.new(SafeFetch::RequestOptions.new(url: url, **)).fetch(&)
  rescue SsrfFilter::InvalidUriScheme, URI::InvalidURIError => e
    raise InvalidUrlError, e.message
  rescue SsrfFilter::Error, Resolv::ResolvError => e
    raise UnsafeUrlError, e.message
  end

  def self.allow_private_network?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('SAFE_FETCH_ALLOW_PRIVATE_NETWORK', false))
  end

  # Exceção estreita: libera só IP literal + porta listados em SAFE_FETCH_PRIVATE_ALLOWLIST
  # (ex.: "100.64.0.1:8788"). Hostname nunca entra, para não abrir DNS rebinding.
  def self.private_allowlisted?(uri)
    entries = ENV.fetch('SAFE_FETCH_PRIVATE_ALLOWLIST', '').split(',').map(&:strip).compact_blank
    return false if entries.empty?

    IPAddr.new(uri.hostname)
    entries.include?("#{uri.hostname}:#{uri.port}")
  rescue IPAddr::InvalidAddressError
    false
  end
end
