# frozen_string_literal: true

require 'json'
require 'net/http'
require 'openssl'
require 'timeout'

# No request, response body, token or credential is ever logged here.
module RegistrationTurnstile
  ENDPOINT = URI('https://challenges.cloudflare.com/turnstile/v0/siteverify').freeze
  ACTION = 'registration'
  HOSTNAMES = %w[circle-book.com www.circle-book.com].freeze

  class << self
    def configure(site_key: nil, secret_key: nil, required: false)
      @site_key = site_key.to_s.strip
      @secret_key = secret_key.to_s.strip
      @required = required || !@site_key.empty? || !@secret_key.empty?
    end

    def required?
      @required == true
    end

    def configured?
      !@site_key.to_s.empty? && !@secret_key.to_s.empty?
    end

    def site_key
      @site_key if configured?
    end

    # The production file is provisioned by deployment, outside the repository.
    # Invalid/missing settings close registration only, not browsing or login.
    def load_configuration(production:, path:, environment: ENV)
      values = if production
                 JSON.parse(File.read(path))
               else
                 { 'site_key' => environment['TURNSTILE_SITE_KEY'],
                   'secret_key' => environment['TURNSTILE_SECRET_KEY'] }
               end
      raise TypeError unless values.is_a?(Hash)
      configure(site_key: values['site_key'], secret_key: values['secret_key'], required: production)
    rescue SystemCallError, JSON::ParserError, TypeError
      configure(required: production)
    end

    # :accepted, :rejected, :unavailable; strictly verify the origin and purpose.
    def verify(token)
      return :accepted unless required?
      return :unavailable unless configured?
      return :rejected unless token.is_a?(String) && token.bytesize.between?(1, 2048) && !token.strip.empty?

      result = exchange(token)
      return :unavailable unless result.is_a?(Hash)
      return :unavailable if (Array(result['error-codes']) & %w[internal-error invalid-input-secret missing-input-secret]).any?
      return :rejected unless result['success'] == true
      return :rejected unless HOSTNAMES.include?(result['hostname']) && result['action'] == ACTION

      :accepted
    rescue Timeout::Error, IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError,
           JSON::ParserError, Net::HTTPBadResponse, Net::ProtocolError
      :unavailable
    end

    private

    def exchange(token)
      # Disable ambient proxy configuration; credentials go only to this HTTPS endpoint.
      http = Net::HTTP.new(ENDPOINT.host, ENDPOINT.port, nil)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.open_timeout = 2
      http.read_timeout = 3
      http.write_timeout = 3 if http.respond_to?(:write_timeout=)
      http.max_retries = 0
      request = Net::HTTP::Post.new(ENDPOINT.request_uri)
      request.set_form_data('secret' => @secret_key, 'response' => token)
      # A total deadline also bounds a response that trickles bytes indefinitely.
      Timeout.timeout(6) do
        response = http.request(request)
        return nil unless response.is_a?(Net::HTTPSuccess)
        return nil if response.body.to_s.bytesize > 16_384
        JSON.parse(response.body)
      end
    end
  end
end
