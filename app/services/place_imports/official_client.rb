require 'net/http'
require 'uri'

module PlaceImports
  # Only this reviewed public source is reachable; redirects are never followed.
  class OfficialClient
    HOST = 'www.se-sports.or.jp'.freeze
    MAX_BYTES = 2.megabytes
    class FetchError < StandardError; end

    def initialize(interval: 1)
      @interval = interval
      @last_request = nil
    end

    def get(url)
      uri = URI.parse(url)
      unless approved_uri?(uri)
        raise FetchError, 'unapproved_url'
      end
      if @last_request
        delay = @interval - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @last_request)
        sleep delay if delay.positive?
      end
      @last_request = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      body = +''
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10, write_timeout: 5) do |http|
        http.max_retries = 0
        request = Net::HTTP::Get.new(uri.request_uri, 'User-Agent' => 'CircleBookFacilityImporter/1.0 (+https://circle-book.com/places)', 'Accept-Encoding' => 'identity')
        http.request(request) do |response|
          return '' if uri.path == '/robots.txt' && response.code == '404'
          raise FetchError, 'http_error' unless response.is_a?(Net::HTTPSuccess)
          response.read_body do |chunk|
            body << chunk
            raise FetchError, 'response_too_large' if body.bytesize > MAX_BYTES
          end
        end
      end
      body.force_encoding(Encoding::UTF_8)
      raise FetchError, 'invalid_encoding' unless body.valid_encoding?
      body
    rescue URI::InvalidURIError, IOError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, Net::HTTPBadResponse
      raise FetchError, 'network_error'
    end

    private

    def approved_uri?(uri)
      uri.scheme == 'https' && uri.host == HOST && uri.port == 443 && uri.userinfo.nil? && uri.query.nil? &&
        (uri.path == '/robots.txt' || uri.path.match?(%r{\A/(facility|facilityinfo)/[a-z0-9/-]*\z}))
    end
  end
end
