require 'minitest/autorun'
require_relative '../../app/services/published_sitemap'

class PublishedSitemapTest < Minitest::Test
  NS = 'http://www.sitemaps.org/schemas/sitemap/0.9'

  def compressed(xml)
    io = StringIO.new
    Zlib::GzipWriter.wrap(io) { |writer| writer.write(xml) }
    io.string
  end

  def test_index_uses_same_domain_children
    xml = %(<sitemapindex xmlns="#{NS}"><sitemap><loc>#{PublishedSitemap::ORIGIN}sitemap6.xml.gz</loc></sitemap></sitemapindex>)
    result = PublishedSitemap.decode(compressed(xml), index: true)
    assert_includes result, 'https://circle-book.com/sitemaps/sitemap6.xml'
    refute_includes result, 'amazonaws.com'
  end

  def test_child_preserves_urls_and_lastmod
    xml = %(<urlset xmlns="#{NS}"><url><loc>https://circle-book.com/circles/123</loc><lastmod>2026-10-04</lastmod></url></urlset>)
    assert_equal xml, PublishedSitemap.decode(compressed(xml), index: false)
  end

  def test_unexpected_child_host_is_rejected
    xml = %(<sitemapindex xmlns="#{NS}"><sitemap><loc>https://example.com/sitemap1.xml.gz</loc></sitemap></sitemapindex>)
    assert_raises(PublishedSitemap::Unavailable) { PublishedSitemap.decode(compressed(xml), index: true) }
  end

  def test_invalid_xml_is_rejected
    assert_raises(PublishedSitemap::Unavailable) { PublishedSitemap.decode(compressed('<html>error</html>'), index: true) }
    assert_raises(PublishedSitemap::Unavailable) { PublishedSitemap.decode(compressed('<urlset>'), index: false) }
  end

  def test_paths_cannot_select_other_s3_objects
    ['../other', 'https://example.com', 'sitemap0', 'sitemap1.xml'].each do |name|
      assert_raises(PublishedSitemap::NotFound) { PublishedSitemap.fetch(name) }
    end
  end
end
