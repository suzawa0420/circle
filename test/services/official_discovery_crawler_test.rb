require 'minitest/autorun'
require_relative '../../app/services/place_imports/official_discovery_crawler'

class OfficialDiscoveryCrawlerTest < Minitest::Test
  ROOT = 'https://www.pref.example.jp/'
  class Client
    attr_reader :calls
    def initialize(pages); @pages, @calls = pages, []; end
    def get(url)
      @calls << url
      value = @pages.fetch(url)
      raise 'do not expose secret response' if value == :failure
      value
    end
  end

  def crawler(pages)
    @client = Client.new(pages)
    PlaceImports::OfficialDiscoveryCrawler.new(config: { root: ROOT, prefecture: 'テスト県' }, client: @client)
  end

  def test_exact_host_query_fragment_and_literal_address_guards
    pages = { ROOT + 'robots.txt' => '', ROOT => '<h1>ホーム</h1><a href="https://elsewhere.jp/gym">体育館</a><a href="/gym?q=1">体育館</a><a href="/gym#x">体育館</a><a href="/gym">体育館</a>', ROOT + 'gym' => '<h1>中央体育館</h1>' }
    result = crawler(pages).call
    assert_equal [ROOT + 'robots.txt', ROOT, ROOT + 'gym'], @client.calls
    assert_equal ['中央体育館'], result[:candidates].map { |x| x['name'] }
    assert result[:state]['complete']
    assert_raises(ArgumentError) { PlaceImports::OfficialDiscoveryCrawler.new(config: { root: 'https://127.0.0.1/', prefecture: 'x' }, client: @client) }
  end

  def test_robots_all_groups_fail_closed_and_never_return_blocked_candidates
    c = crawler(ROOT + 'robots.txt' => "User-agent: another-bot\nDisallow: /gym\n", ROOT => '<a href="/gym">体育館</a>')
    result = c.call
    assert_empty result[:candidates]
    assert_equal 1, result[:counters][:blocked]
    refute_includes @client.calls, ROOT + 'gym'
  end

  def test_sitemap_cursor_is_bounded_and_rescan_is_explicit
    pages = { ROOT + 'robots.txt' => "Sitemap: #{ROOT}sitemap.xml\n", ROOT => '<h1>ホーム</h1>', ROOT + 'sitemap.xml' => '<urlset>' + (1..5).map { |i| "<url><loc>#{ROOT}gym#{i}</loc></url>" }.join + '</urlset>' }
    5.times { |i| pages[ROOT + "gym#{i + 1}"] = "<h1>体育館#{i + 1}</h1>" }
    c = crawler(pages)
    first = c.call
    assert_equal 3, first[:counters][:fetched]
    refute first[:state]['complete']
    second = c.call(state: first[:state])
    assert_equal 3, second[:counters][:fetched]
    final = c.call(state: second[:state])
    assert final[:state]['complete']
    before = @client.calls.length
    c.call(state: final[:state])
    assert_equal before, @client.calls.length
    assert_equal 3, c.call(state: final[:state], rescan: true)[:counters][:fetched]
  end

  def test_network_retries_bounded_and_error_text_not_exposed
    c = crawler(ROOT + 'robots.txt' => '', ROOT => :failure)
    result = c.call
    assert_equal 2, @client.calls.count(ROOT)
    assert result[:state]['complete']
    assert_equal ['fetch_failed'], result[:errors]
    refute_includes result.inspect, 'secret'
  end

  def test_robots_failure_makes_no_page_requests
    c = crawler(ROOT + 'robots.txt' => :failure)
    result = c.call
    assert_equal ['robots_unavailable'], result[:errors]
    assert_equal [ROOT + 'robots.txt'], @client.calls
    refute result[:state]['initialized']
  end

  def test_external_sitemap_and_xml_entities_not_followed
    pages = { ROOT + 'robots.txt' => "Sitemap: https://other.jp/sitemap.xml\nSitemap: #{ROOT}sitemap.xml", ROOT => '<h1>home</h1>', ROOT + 'sitemap.xml' => '<?xml version="1.0"?><!DOCTYPE x [<!ENTITY ext SYSTEM "file:///etc/passwd">]><urlset><url><loc>&ext;</loc></url></urlset>' }
    result = crawler(pages).call
    assert_empty result[:candidates]
    assert_equal [ROOT + 'robots.txt', ROOT, ROOT + 'sitemap.xml'], @client.calls
  end
  def test_home_navigation_is_followed
    pages = { ROOT + 'robots.txt' => '', ROOT => '<nav><a href="/facility">体育館</a></nav>', ROOT + 'facility' => '<h1>市立体育館</h1>' }
    result = crawler(pages).call
    assert_equal ['市立体育館'], result[:candidates].map { |x| x['name'] }
  end

  def test_capacity_truncation_still_drains_retained_frontier
    pages = { ROOT + 'robots.txt' => '', ROOT => (1..2005).map { |i| "<a href=\"/gym#{i}\">体育館</a>" }.join }
    2005.times { |i| pages[ROOT + "gym#{i + 1}"] = '<h1>体育館</h1>' }
    c = crawler(pages)
    first = c.call
    assert first[:state]['capacity_reached']
    refute first[:state]['complete']
    assert_operator first[:state]['seen'].size + first[:state]['frontier'].size, :<=, 2000
    second = c.call(state: first[:state])
    assert_equal 3, second[:counters][:fetched]
    assert_includes second[:errors], 'capacity_reached'
    # A retained final frontier item must finish even after truncation.
    state = { 'initialized' => true, 'capacity_reached' => true, 'frontier' => [ROOT + 'gym1'] }
    final = c.call(state: state)
    assert final[:state]['complete']
    assert final[:state]['capacity_reached']
  end

  def test_html_robots_response_fails_closed
    c = crawler(ROOT + 'robots.txt' => '<html>Access denied</html>')
    result = c.call
    assert_equal ['robots_unavailable'], result[:errors]
    assert_equal [ROOT + 'robots.txt'], @client.calls
  end

  def test_configured_entrypoints_are_host_restricted
    pages = { ROOT + 'robots.txt' => '', ROOT => '<h1>ホーム</h1>', ROOT + '123.html' => '<h1>公式体育館一覧</h1>' }
    client = Client.new(pages)
    c = PlaceImports::OfficialDiscoveryCrawler.new(config: { root: ROOT, prefecture: 'テスト県', entrypoints: [ROOT + '123.html', 'https://elsewhere.jp/123'] }, client: client)
    result = c.call
    assert_equal [ROOT + '123.html'], result[:candidates].map { |x| x['url'] }
    assert_equal 3, client.calls.length
  end

  def test_percent_encoded_path_cannot_bypass_robots
    pages = { ROOT + 'robots.txt' => "Disallow: /gym\n", ROOT => '<a href="/%67ym">体育館</a>' }
    result = crawler(pages).call
    assert_equal 1, result[:counters][:blocked]
    refute_includes @client.calls, ROOT + '%67ym'
  end

end
