require 'test_helper'
require 'minitest/mock'

class PlaceImportsSourceTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  class Client
    attr_reader :requests
    def initialize(pages)
      @pages, @requests = pages, []
    end
    def get(url)
      @requests << url
      @pages.fetch(URI(url).path)
    end
  end

  setup do
    @pages = {
      '/robots.txt' => 'User-agent: *',
      '/facility/' => '<a href="/facility/test/">体育館</a><a href="https://evil.test/facility/bad/">外部</a>',
      '/facility/test/' => '<h2 class="c-mv__title">テスト体育館</h2><dl><div class="c-summaryTable__item"><dt>住所</dt><dd>〒158-0086 東京都世田谷区尾山台3-19-3</dd></div></dl><a class="p-facility-singleTab__facilityinfoLink" href="/facilityinfo/test-gym/">体育館</a>',
      '/facilityinfo/test-gym/' => '<main><nav>テニス</nav><div><h2>基本情報</h2><p>バスケットボール 1面</p><h2>利用料金</h2><p>卓球教室については別施設へ</p></div></main>'
    }
  end

  test 'collects factual sports from basic information excluding navigation and other sections' do
    client = Client.new(@pages)
    data = PlaceImports::SetagayaSource.new(client: client).collect.sole
    assert_equal ['バスケットボール'], data['sports']
    assert_equal '東京都世田谷区尾山台3-19-3', data['address']
    assert_equal '1', data['tag']
    assert_equal 4, client.requests.size
  end

  test 'robots wildcard exclusions fail closed before facility fetch' do
    @pages['/robots.txt'] = "User-agent: *\nDisallow: /facility/*"
    client = Client.new(@pages)
    assert_raises(PlaceImports::SetagayaSource::SourceError) { PlaceImports::SetagayaSource.new(client: client).collect }
    assert_equal ['https://www.se-sports.or.jp/robots.txt'], client.requests
  end

  test 'closed facility alerts are retained without extracting footer sport labels' do
    @pages['/facility/test/'] += '<h4 class="c-news__itemTitle">改修工事に伴う休館のお知らせ</h4><footer>バドミントン</footer>'
    data = PlaceImports::SetagayaSource.new(client: Client.new(@pages)).collect.sole
    assert_equal ['改修工事に伴う休館のお知らせ'], data['alerts']
    assert_equal ['バスケットボール'], data['sports']
  end

  test 'network failures are sanitized and redirects and oversized responses are rejected' do
    client = PlaceImports::OfficialClient.new(interval: 0)
    Net::HTTP.stub(:start, ->(*) { raise SocketError, 'network internals' }) do
      error = assert_raises(PlaceImports::OfficialClient::FetchError) { client.get('https://www.se-sports.or.jp/facility/') }
      assert_equal 'network_error', error.message
    end
    [Net::HTTPFound.new('1.1', '302', 'Found'), Net::HTTPOK.new('1.1', '200', 'OK')].each do |response|
      response.define_singleton_method(:read_body) { |&block| block.call('a' * (PlaceImports::OfficialClient::MAX_BYTES + 1)) }
      transport = Object.new
      transport.define_singleton_method(:max_retries=) { |_| }
      transport.define_singleton_method(:request) { |_, &block| block.call(response) }
      Net::HTTP.stub(:start, ->(*_, **_, &block) { block.call(transport) }) do
        assert_raises(PlaceImports::OfficialClient::FetchError) { client.get('https://www.se-sports.or.jp/facility/') }
      end
    end
  end

  test 'unsupported sport mentions without court counts do not become sports' do
    @pages['/facilityinfo/test-gym/'] = '<main><h2>基本情報</h2><p>ソフトテニス 2面。バスケットボールは利用できません</p><h2>利用料金</h2></main>'
    data = PlaceImports::SetagayaSource.new(client: Client.new(@pages)).collect.sole
    assert_empty data['sports']
  end

  test 'client rejects non official URLs schemes credentials queries and paths before network access' do
    client = PlaceImports::OfficialClient.new(interval: 0)
    ['http://www.se-sports.or.jp/facility/', 'https://127.0.0.1/facility/', 'https://www.se-sports.or.jp.evil.test/facility/',
      'https://user:password@www.se-sports.or.jp/facility/', 'https://www.se-sports.or.jp/facility/?q=1', 'https://www.se-sports.or.jp/admin/'].each do |url|
      assert_raises(PlaceImports::OfficialClient::FetchError) { client.get(url) }
    end
  end
end
