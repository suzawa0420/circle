require 'net/http'
require 'zlib'
require 'stringio'
require 'nokogiri'

# Read only the existing public sitemap objects; no AWS credentials are needed.
class PublishedSitemap
  ORIGIN = 'https://s3-ap-northeast-1.amazonaws.com/circlebook/sitemaps/'.freeze
  PUBLIC_ORIGIN = 'https://circle-book.com/sitemaps/'.freeze
  MAX_BYTES = 50 * 1024 * 1024
  class Unavailable < StandardError; end
  class NotFound < StandardError; end

  def self.fetch(name)
    raise NotFound unless /\Asitemap(?:[1-9][0-9]*)?\z/.match?(name)

    uri = URI("#{ORIGIN}#{name}.xml.gz")
    compressed = ''.b
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 3, read_timeout: 10) do |http|
      http.request(Net::HTTP::Get.new(uri.request_uri)) do |response|
        raise NotFound if response.code == '404'
        raise Unavailable unless response.is_a?(Net::HTTPSuccess)

        response.read_body do |chunk|
          raise Unavailable if compressed.bytesize + chunk.bytesize > MAX_BYTES
          compressed << chunk
        end
      end
    end
    decode(compressed, index: name == 'sitemap')
  rescue Timeout::Error, SocketError, IOError, SystemCallError, OpenSSL::SSL::SSLError, Zlib::Error
    raise Unavailable
  end

  def self.decode(compressed, index:)
    xml = Zlib::GzipReader.wrap(StringIO.new(compressed)) { |reader| reader.read(MAX_BYTES + 1) }
    raise Unavailable if xml.bytesize > MAX_BYTES

    document = Nokogiri::XML(xml) { |config| config.strict.nonet }
    # SitemapGenerator uses a plain urlset at the main URL when no split is needed.
    allowed_roots = index ? %w[sitemapindex urlset] : %w[urlset]
    raise Unavailable unless allowed_roots.include?(document.root&.name) &&
                             document.root.namespace&.href == 'http://www.sitemaps.org/schemas/sitemap/0.9'
    return xml if document.root.name == 'urlset'

    document.xpath('//sm:sitemap/sm:loc', 'sm' => 'http://www.sitemaps.org/schemas/sitemap/0.9').each do |location|
      name = location.content.delete_prefix(ORIGIN)
      raise Unavailable unless /\Asitemap[1-9][0-9]*\.xml\.gz\z/.match?(name)
      location.content = PUBLIC_ORIGIN + name.delete_suffix('.gz')
    end
    document.to_xml
  rescue Nokogiri::XML::SyntaxError, Zlib::Error
    raise Unavailable
  end
end
