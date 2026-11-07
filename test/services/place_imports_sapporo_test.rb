require 'test_helper'

class PlaceImportsSapporoTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  class Client
    attr_reader :requests
    def initialize(pages); @pages, @requests = pages, []; end
    def get(url); @requests << url; @pages.fetch(url); end
  end

  setup do
    @root = PlaceImports::SapporoSource::ROOT
    @url = "#{@root}/sports/sisetsu/institution/gym/higashi.html"
    @pages = { "#{@root}/robots.txt" => "User-agent: *\nDisallow:\n",
      @url => fixture('higashi'), PlaceImports::SapporoSource::FEES => fixture('fees'),
      PlaceImports::SapporoSource::EAST_HOURS => fixture('ward') }
    @client = Client.new(@pages)
    @source = PlaceImports::SapporoSource.new(client: @client)
  end

  test 'collects municipal gym facts and current qualified fees without obsolete ward fees' do
    data = @source.fetch(@url)
    assert_equal '東区体育館', data['name']
    assert_equal '北海道札幌市東区北27条東14丁目3-1', data['address']
    assert_equal '札幌市', data['city']
    assert_equal '1', data['tag']
    assert_equal '9時00分～21時00分', data['time']
    assert_equal '100台', data['parking']
    assert_includes data['sports'], 'バスケットボール'
    assert_includes data['scale'], 'バスケットボール | 2面'
    assert_includes data['access'], '元町'
    assert_includes data['regular_holiday'], '祝日の場合は第2月曜日'
    assert_includes data['price'], '430円'
    assert_includes data['price'], '各時間帯ごとに料金が必要'
    assert_includes data['price'], '別途使用料'
    assert_includes data['price'], '障害者手帳'
    assert_not_includes data['price'], '390円'
    assert_empty data['alerts']
    assert_equal "#{@root}/robots.txt", @client.requests.first
  end

  test 'missing hours and historical construction remain unconfirmed' do
    url = @url.sub('higashi', 'kita')
    @pages[url] = fixture('kita')
    data = @source.fetch(url)
    assert_nil data['time']
    assert data['alerts'].any? { |text| text.include?('工事') }
    assert_not_includes @client.requests, PlaceImports::SapporoSource::EAST_HOURS
  end

  test 'changed or image only fee tables do not manufacture prices' do
    @pages[PlaceImports::SapporoSource::FEES] = '<div id="tmp_contents"><h3>体育館</h3><p>各区体育館</p><img src="fees.png"></div>'
    assert_nil @source.fetch(@url)['price']
  end

  test 'mismatched companion page cannot provide opening hours' do
    @pages[PlaceImports::SapporoSource::EAST_HOURS] = fixture('ward').sub('011-751-5250', '011-000-0000')
    assert_nil @source.fetch(@url)['time']
  end

  test 'robots wildcard denial precedes fetching protected content' do
    @pages["#{@root}/robots.txt"] = "User-agent: *\nDisallow: /sports/*\n"
    assert_raises(PlaceImports::SapporoSource::SourceError) { @source.fetch(@url) }
    assert_equal ["#{@root}/robots.txt"], @client.requests
  end

  test 'seeds are limited and unapproved URLs are rejected before requests' do
    assert_equal 2, @source.seeds.size
    assert_raises(PlaceImports::SapporoSource::SourceError) { @source.fetch('https://example.com/gym.html') }
    assert_empty @client.requests
  end

  test 'client only allows reviewed HTTPS paths without redirects query or credentials' do
    client = PlaceImports::SapporoClient.new
    assert client.send(:approved_uri?, URI(@url))
    [@url.sub('https:', 'http:'), @url + '?x=1', @url + '#x', @url.sub('www.city.sapporo.jp', 'city.sapporo.jp.evil.test'),
      "#{@root}/sports/unknown.html", @url.sub('https://', 'https://user@')].each do |url|
      assert_not client.send(:approved_uri?, URI(url)), url
    end
  end

  test 'outdoor tennis preserves seasonal hours court count and qualified charges' do
    @pages[PlaceImports::SapporoSource::TENNIS] = fixture('hiragishi')
    @pages[PlaceImports::SapporoSource::OUTDOOR_FEES] = fixture('outdoorfees')
    data = @source.fetch(PlaceImports::SapporoSource::TENNIS)
    assert_equal '平岸庭球場', data['name']
    assert_equal '2', data['tag']
    assert_equal ['テニス'], data['sports']
    assert_includes data['scale'], '20面'
    assert_includes data['time'], '土日祝日'
    assert_includes data['regular_holiday'], '4月29日から10月31日まで'
    assert_includes data['price'], '1,700'
    assert_includes data['price'], '850'
    assert_equal 3, data['price'].scan('1,700 | 850').size
    assert_includes data['price'], '区分 | 期間 | 時間帯 | 一般 | 高校生以下'
    assert_includes data['price'], '高校生以下'
    assert_includes data['price'], '入場料を徴収する場合は料金が異なります'
    assert_includes data['price'], '別途使用料'
    assert_not_includes data['price'], '月寒'
    assert_not_includes data['price'], '弓道'
    # The municipal outdoor table does not state a currency unit.
    assert_not_includes data['price'], '1,700円'
    assert_includes data['access'], '徒歩12分'
    assert_equal '100台程度', data['parking']
    assert_empty data['alerts']
  end

  test 'verified tennis payload matches the existing city rather than inventing a ward master' do
    @pages[PlaceImports::SapporoSource::TENNIS] = fixture('hiragishi')
    @pages[PlaceImports::SapporoSource::OUTDOOR_FEES] = fixture('outdoorfees')
    category = Category.create!(name: '球技', kana: 'sapporo-ball', order: '1')
    Event.create!(name: 'テニス', ruby: 'sapporo-tennis', category: category, place: 1, order: '1')
    prefecture = Prefecture.create!(name: '北海道', kana: 'sapporo-hokkaido', order: '1')
    City.create!(name: '札幌市', city_kana: 'sapporo', prefecture: prefecture)
    run = PlaceImportRun.create!(source: @source.key, mode: 'preview')
    candidate = PlaceImportCandidate.create!(source: @source.key, source_url: PlaceImports::SapporoSource::TENNIS,
      fingerprint: 'sapporo-city-mapping', checked_at: Time.current, place_import_run: run,
      payload: @source.fetch(PlaceImports::SapporoSource::TENNIS), status: 'collected')
    assert_no_difference('Place.count') do
      assert_equal 'ready', PlaceImports::Registrar.new.call(candidate, apply: false)
    end
  end

  test 'each discovery rereads the bounded official listing including new facility links' do
    @pages[PlaceImports::SapporoSource::DIRECTORY] = fixture('directory')
    first = @source.discover
    assert first.any? { |item| item['url'] == PlaceImports::SapporoSource::TENNIS }
    @pages[PlaceImports::SapporoSource::DIRECTORY] = fixture('directory').sub('</div>', '<a href="/sports/sisetsu/institution/tennis/newcourt.html">新しい庭球場</a></div>')
    assert_equal first.size + 1, @source.discover.size
    assert_equal 2, @client.requests.count(PlaceImports::SapporoSource::DIRECTORY)
    @pages[PlaceImports::SapporoSource::DIRECTORY] = fixture('directory').sub('</div>', '<a href="https://evil.example/sports/sisetsu/institution/tennis/bad.html">bad</a></div>')
    assert_equal first, @source.discover
    @pages[PlaceImports::SapporoSource::DIRECTORY] = fixture('directory').sub('<h1>', '<a href="mailto:">mail</a><a href="https://[bad">bad</a><h1>')
    assert_equal first, @source.discover
  end

  test 'changed empty or paginated listing does not claim completion' do
    @pages[PlaceImports::SapporoSource::DIRECTORY] = '<div id="tmp_contents"><h1>スポーツ施設</h1><h2>施設一覧</h2></div>'
    assert_raises(PlaceImports::SapporoSource::SourceError) { @source.discover }
    @pages[PlaceImports::SapporoSource::DIRECTORY] = fixture('directory').sub('</div>', '<a rel="next" href="?page=2">次へ</a></div>')
    assert_raises(PlaceImports::SapporoSource::SourceError) { @source.discover }
  end

  test 'gym and outdoor table-only closure notices block automatic publication' do
    notice = '<table><tr><th>お知らせ</th><td>改修工事のため利用休止</td></tr></table>'
    @pages[@url] = fixture('higashi').sub('</div>', "#{notice}</div>")
    assert_includes @source.fetch(@url)['alerts'], '改修工事のため利用休止'
    @pages[PlaceImports::SapporoSource::TENNIS] = fixture('hiragishi').sub('</div>', "#{notice}</div>")
    @pages[PlaceImports::SapporoSource::OUTDOOR_FEES] = fixture('outdoorfees')
    assert_includes @source.fetch(PlaceImports::SapporoSource::TENNIS)['alerts'], '改修工事のため利用休止'
  end

  test 'outdoor prices fail closed if qualification structure changes or conditions disappear' do
    @pages[PlaceImports::SapporoSource::TENNIS] = fixture('hiragishi')
    @pages[PlaceImports::SapporoSource::OUTDOOR_FEES] = fixture('outdoorfees').sub('<h2>利用料金表</h2>', '<h2>利用料金と注意事項</h2>')
    assert_nil @source.fetch(PlaceImports::SapporoSource::TENNIS)['price']
    @pages[PlaceImports::SapporoSource::OUTDOOR_FEES] = fixture('outdoorfees').sub('入場料を徴収する場合', '条件変更')
    assert_nil @source.fetch(PlaceImports::SapporoSource::TENNIS)['price']
  end

  private

  def fixture(name)
    File.read(Rails.root.join('test/fixtures/files/place_imports/sapporo', "#{name}.html"))
  end
end
