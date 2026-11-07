require 'net/http'
require 'uri'

module PlaceImports
  # Deliberately independent of the HTML-only client: PDF bytes are never decoded
  # or executed. Only one manually reviewed document may be downloaded.
  class KochiClient < OfficialClient
    HOST = 'www.kc-sports.or.jp'.freeze
    PDF_PATH = '/uploads/s300fee20261001.pdf'.freeze
    PATHS = ['/robots.txt', '/', '/facilities/f300/f305/', '/facilities/f300/',
             '/facilities/costs/', '/i0002025006/', PDF_PATH].freeze
    MAX_BYTES = 2.megabytes

    def get(url)
      uri = URI.parse(url)
      raise FetchError, 'unapproved_url' unless approved_uri?(uri)
      if @last_request
        delay = [@interval, 1].max - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @last_request)
        sleep delay if delay.positive?
      end
      @last_request = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      body = +''.b
      pdf = uri.path == PDF_PATH
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10, write_timeout: 5) do |http|
        http.max_retries = 0
        request = Net::HTTP::Get.new(uri.request_uri, 'User-Agent' => 'CircleBookFacilityImporter/1.0 (+https://circle-book.com/places)', 'Accept-Encoding' => 'identity')
        http.request(request) do |response|
          return '' if uri.path == '/robots.txt' && response.code == '404'
          raise FetchError, 'http_error' unless response.is_a?(Net::HTTPSuccess)
          raise FetchError, 'invalid_content_type' if pdf && response.content_type != 'application/pdf'
          raise FetchError, 'response_too_large' if response['content-length'].to_i > MAX_BYTES
          response.read_body do |chunk|
            body << chunk.b
            raise FetchError, 'response_too_large' if body.bytesize > MAX_BYTES
          end
        end
      end
      if pdf
        raise FetchError, 'invalid_pdf' unless body.start_with?('%PDF-') && body.rstrip.end_with?('%%EOF')
      else
        body.force_encoding(Encoding::UTF_8)
        raise FetchError, 'invalid_encoding' unless body.valid_encoding?
      end
      body
    rescue URI::InvalidURIError, IOError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, Net::HTTPBadResponse
      raise FetchError, 'network_error'
    end

    private

    def approved_uri?(uri)
      uri.scheme == 'https' && uri.host == HOST && uri.port == 443 && uri.userinfo.nil? &&
        uri.query.nil? && uri.fragment.nil? && PATHS.include?(uri.path)
    end
  end
end
