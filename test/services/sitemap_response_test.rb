require 'minitest/autorun'
require 'minitest/mock'
require 'rails'
require 'action_controller/railtie'
require_relative '../../app/services/published_sitemap'
require_relative '../../app/controllers/sitemaps_controller'

# No application boot, production configuration, or database is used.
class SitemapResponseTest < Minitest::Test
  def setup
    @previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  def teardown
    Rails.cache = @previous_cache
  end

  def request
    SitemapsController.action(:index).call(Rack::MockRequest.env_for('/sitemap'))
  end

  def test_returns_xml_directly_and_caches_it
    calls = 0
    PublishedSitemap.stub(:fetch, ->(name) { calls += 1; assert_equal 'sitemap', name; '<sitemapindex/>' }) do
      status, headers, body = request
      assert_equal 200, status
      assert_includes headers['content-type'], 'application/xml'
      assert_includes headers['cache-control'], 'public'
      assert_includes headers['cache-control'], 'max-age=300'
      refute headers.key?('location')
      assert_equal '<sitemapindex/>', body.each.to_a.join
      assert_equal 200, request.first
      assert_equal 1, calls
    end
  end

  def test_temporary_upstream_failure_is_not_cached_as_success
    PublishedSitemap.stub(:fetch, ->(_) { raise PublishedSitemap::Unavailable }) do
      status, headers, = request
      assert_equal 503, status
      assert_equal 'no-store', headers['cache-control']
      assert_equal '300', headers['retry-after']
    end
  end

  def test_missing_object_returns_404
    PublishedSitemap.stub(:fetch, ->(_) { raise PublishedSitemap::NotFound }) do
      assert_equal 404, request.first
    end
  end
end
