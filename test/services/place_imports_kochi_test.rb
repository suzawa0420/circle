require 'test_helper'

class PlaceImportsKochiTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  class Client
    attr_reader :requests
    def initialize(pages); @pages, @requests = pages, []; end
    def get(url); @requests << url; @pages.fetch(url); end
  end

  setup do
    @root = PlaceImports::KochiSource::ROOT
    @url = PlaceImports::KochiSource::URL
    @pdf = PlaceImports::KochiSource::PDF_URL
    @pages = { "#{@root}/robots.txt" => "User-agent: *\nDisallow: /wp-admin/\n" }
    { '/facilities/f300/f305/' => 'tobu', '/facilities/f300/' => 'tobu-access', '/facilities/costs/' => 'costs', '/i0002025006/' => 'fee-notice', '/' => 'index' }.each do |path, file|
      @pages["#{@root}#{path}"] = File.read(Rails.root.join("test/fixtures/files/place_imports/kochi/#{file}.html"))
    end
    @pages[@pdf] = File.binread(Rails.root.join('test/fixtures/files/place_imports/kochi/s300fee20261001.pdf'))
    @client = Client.new(@pages)
    @source = PlaceImports::KochiSource.new(client: @client)
  end

  test 'reviewed outdoor identity preserves contact context and complete scoped tariff' do
    data = @source.fetch(@url)
    assert_equal '東部総合運動場テニスコート', data['name']
    assert_equal '高知県高知市介良1221-1', data['address']
    assert_equal '088-878-1150', data['tel']
    assert_equal '2', data['tag']
    assert_equal ['テニス'], data['sports']
    assert_nil data['city']
    assert_equal '130台', data['parking']
    assert_equal '日の出～21:00', data['time']
    assert_equal '年末年始（12/29～1/3）', data['regular_holiday']
    ['親施設', '高知駅から車で15分', '高知I.C.から車で15分', '高知龍馬空港から車で25分', '東部野球場前下車徒歩3分'].each { |s| assert_includes data['access'], s }
    ['くろしおアリーナ事務所', '砂入り人工芝全16コート', 'ソフトテニス', '1～8番', '5，6月は1～5番', '15～20分', '連続投入'].each { |s| assert_includes data['scale'], s }
    ['入場料・会費等を徴収しない', '1面、税込', '高校生以下：1時間530円', '午前8:00～12:00 1,350円', '午後13:00～17:00 1,350円', '1日8:00～17:00 2,700円', 'その他：1時間780円', '午前8:00～12:00 2,360円', '午後13:00～17:00 2,360円', '1日8:00～17:00 4,720円', '1面12分100円', 'クラブハウス：1時間550円', 'シャワー：1回10分100円', '1円代の端数は切捨て', '2026年4月1日からの利用申請分', 'この料金表の対象外', '令和8年4月1日時点'].each { |s| assert_includes data['price'], s }
    assert_not_includes data['price'], 'SHA256'
    assert_not_includes data['price'], '目視'
    assert_not_includes data['scale'], '目視'
    assert_empty data['alerts']
    assert_equal "#{@root}/robots.txt", @client.requests.first
    assert data['evidence'].any? { |e| e['text'].include?(PlaceImports::KochiSource::PDF_SHA256) }
  end

  test 'partial seeds cannot mark the city complete' do
    assert_equal [{ 'url' => @url }], @source.seeds
    assert_equal 'partial_reviewed_seed_only', assert_raises(PlaceImports::KochiSource::SourceError) { @source.discover }.message
    assert_empty @client.requests
  end

  test 'changed PDF hash or current link fails closed without fetching unknown URL' do
    @pages[@pdf] += 'changed'
    assert_raises(PlaceImports::KochiSource::SourceError) { @source.fetch(@url) }
    @pages["#{@root}/facilities/costs/"].gsub!('s300fee20261001.pdf', 's300fee20270101.pdf')
    @client.requests.clear
    assert_equal 'changed_current_rate_link', assert_raises(PlaceImports::KochiSource::SourceError) { @source.fetch(@url) }.message
    assert_not @client.requests.any? { |u| u.end_with?('.pdf') }
  end

  test 'identity photo and mandatory facts must remain present' do
    ['東部総合運動場テニスコート', '介良1221-1', '全16コート', '5a0249179c877292721cf38b7f67ba91.jpg', '130台', '硬式テニス，ソフトテニス', '年末年始（12/29～1/3）'].each do |value|
      original = @pages[@url]
      @pages[@url] = original.gsub(value, '')
      assert_raises(PlaceImports::KochiSource::SourceError, value) { @source.fetch(@url) }
      @pages[@url] = original
    end
  end

  test 'missing news or mandatory fee qualification fails closed' do
    @pages["#{@root}/"].gsub!('新着情報', 'changed')
    assert_raises(PlaceImports::KochiSource::SourceError) { @source.fetch(@url) }
    @pages["#{@root}/"].gsub!('changed', '新着情報')
    @pages["#{@root}/i0002025006/"].gsub!('利用申請分', '利用日')
    assert_raises(PlaceImports::KochiSource::SourceError) { @source.fetch(@url) }
  end

  test 'added qualifications after unchanged fee notice introduction fail closed' do
    @pages["#{@root}/i0002025006/"].sub!('<h2>新料金表</h2>', '<p>追加条件：高校生料金は市内在住者のみ</p><h2>新料金表</h2>')
    assert_equal 'changed_rate_qualifications', assert_raises(PlaceImports::KochiSource::SourceError) { @source.fetch(@url) }.message
    assert_not @client.requests.include?(@pdf)
  end

  test 'bare closure notices and unknown rate changes are retained but never fetched' do
    @pages["#{@root}/"].sub!('新着情報</div>', '新着情報</div><div>東部テニスコートを工事のため休業</div><a href="https://evil.example/">利用料金変更</a>')
    data = @source.fetch(@url)
    assert_includes data['alerts'], '東部テニスコートを工事のため休業'
    assert_includes data['alerts'], '利用料金変更'
    assert_not @client.requests.any? { |u| u.include?('evil') }
  end

  test 'robots applies to PDF and is refreshed each run' do
    @source.fetch(@url)
    @client.requests.clear
    @pages["#{@root}/robots.txt"] = "User-agent: *\nDisallow: /\n"
    assert_raises(PlaceImports::KochiSource::SourceError) { @source.fetch(@url) }
    assert_equal ["#{@root}/robots.txt"], @client.requests
    @pages["#{@root}/robots.txt"] = "Disallow: /uploads/*.pdf$\n"
    assert_equal 'robots_disallowed', assert_raises(PlaceImports::KochiSource::SourceError) { @source.fetch(@url) }.message
    assert_not @client.requests.include?(@pdf)
  end

  test 'untrusted strings are text only and scripts are not evidence' do
    @pages[@url].sub!('130台', '130台 #{raise "executed"}')
    @pages[@url].sub!('</h1>', '</h1><script>raise "executed"</script>')
    data = @source.fetch(@url)
    assert_includes data['parking'], '#{raise "executed"}'
    assert_not_includes data['evidence'].first['text'], '<script>'
  end

  test 'client rejects unreviewed URLs before network' do
    client = PlaceImports::KochiClient.new
    %w[http://www.kc-sports.or.jp/ https://kc-sports.or.jp/ https://www.kc-sports.or.jp/unknown/ https://www.kc-sports.or.jp/?x=1 https://www.kc-sports.or.jp/#x https://user@www.kc-sports.or.jp/ https://www.kc-sports.or.jp/uploads/other.pdf].each do |url|
      assert_raises(PlaceImports::OfficialClient::FetchError) { client.get(url) }
    end
  end

  def with_response(code:, body:, type: 'application/pdf', length: nil)
    response = Net::HTTPResponse::CODE_TO_OBJ.fetch(code).new('1.1', code, 'test')
    response['content-type'] = type
    response['content-length'] = length.to_s if length
    response.define_singleton_method(:read_body) { |&block| block.call(body) }
    http = Object.new
    http.define_singleton_method(:max_retries=) { |_value| }
    http.define_singleton_method(:request) { |_request, &block| block.call(response) }
    original = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start) { |*args, **kwargs, &block| block.call(http) }
    yield PlaceImports::KochiClient.new
  ensure
    Net::HTTP.define_singleton_method(:start, original) if original
  end

  test 'PDF responses require success MIME size signature and binary preservation' do
    with_response(code: '200', body: @pages[@pdf]) { |client| assert_equal @pages[@pdf], client.get(@pdf) }
    [{ code: '302', body: '' }, { code: '403', body: '' }, { code: '200', body: '<html>fake</html>' },
     { code: '200', body: @pages[@pdf], type: 'text/html' },
     { code: '200', body: '', length: PlaceImports::KochiClient::MAX_BYTES + 1 },
     { code: '200', body: 'x' * (PlaceImports::KochiClient::MAX_BYTES + 1) }].each do |args|
      with_response(**args) { |client| assert_raises(PlaceImports::OfficialClient::FetchError) { client.get(@pdf) } }
    end
    with_response(code: '404', body: '') { |client| assert_equal '', client.get("#{@root}/robots.txt") }
    with_response(code: '403', body: '') { |client| assert_raises(PlaceImports::OfficialClient::FetchError) { client.get("#{@root}/robots.txt") } }
    with_response(code: '302', body: '') { |client| assert_raises(PlaceImports::OfficialClient::FetchError) { client.get("#{@root}/robots.txt") } }
  end
end
