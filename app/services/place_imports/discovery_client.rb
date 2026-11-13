require 'ipaddr'
require 'resolv'
require 'timeout'

module PlaceImports
  # Public official host only. Pin a checked public IP to prevent DNS rebinding;
  # preserve TLS hostname verification. Never follow redirects or send cookies.
  class DiscoveryClient < OfficialClient
    BLOCKED = %w[0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
      172.16.0.0/12 192.0.0.0/24 192.168.0.0/16 198.18.0.0/15 224.0.0.0/4
      240.0.0.0/4 ::/128 ::1/128 ::ffff:0:0/96 fc00::/7 fe80::/10 ff00::/8].map { |ip| IPAddr.new(ip) }.freeze

    def initialize(root:, interval: 1)
      super(interval: interval)
      @host = URI.parse(root).host
    end

    def get(url)
      Timeout.timeout(25) { fetch(url) }
    rescue Timeout::Error
      raise FetchError, 'network_error'
    end

    private

    def fetch(url)
      uri = URI.parse(url)
      raise FetchError, 'unapproved_url' unless approved_uri?(uri)
      addresses = Resolv.getaddresses(@host)
      raise FetchError, 'unapproved_url' if addresses.empty? || addresses.any? { |ip| BLOCKED.any? { |range| range.include?(IPAddr.new(ip)) } }
      delay = @last_request ? @interval - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @last_request) : 0
      sleep delay if delay.positive?
      @last_request = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      http = Net::HTTP.new(@host, 443, nil)
      http.ipaddr = addresses.first
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10
      http.write_timeout = 5
      http.max_retries = 0
      body = +''
      request = Net::HTTP::Get.new(uri.request_uri,
        'User-Agent' => 'CircleBookFacilityImporter/1.0 (+https://circle-book.com/places)',
        'Accept-Encoding' => 'identity')
      http.start do
        http.request(request) do |response|
          return '' if uri.path == '/robots.txt' && response.code == '404'
          raise FetchError, 'http_error' unless response.is_a?(Net::HTTPSuccess)
          content_type = response['content-type'].to_s
          raise FetchError, 'invalid_content_type' unless content_type.match?(%r{\A(?:text/(?:html|plain|xml)|application/(?:xml|xhtml\+xml))\b}i)
          response.read_body do |chunk|
            body << chunk
            raise FetchError, 'response_too_large' if body.bytesize > MAX_BYTES
          end
        end
      end
      body.force_encoding(Encoding::UTF_8)
      raise FetchError, 'invalid_encoding' unless body.valid_encoding?
      body
    rescue URI::InvalidURIError, IPAddr::InvalidAddressError, Resolv::ResolvError, IOError, SocketError,
      SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, Net::HTTPBadResponse
      raise FetchError, 'network_error'
    end

    private

    def approved_uri?(uri)
      uri.scheme == 'https' && uri.host == @host && uri.port == 443 && uri.userinfo.nil? &&
        uri.query.nil? && uri.fragment.nil? && uri.path.start_with?('/')
    end
  end
end
