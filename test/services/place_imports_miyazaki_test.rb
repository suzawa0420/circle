require 'test_helper'

class PlaceImportsMiyazakiTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  class Client
    attr_reader :requests
    def initialize(pages); @pages, @requests = pages, []; end
    def get(url); @requests << url; @pages.fetch(url); end
  end

  setup do
    @root = PlaceImports::MiyazakiSource::ROOT
    @url = PlaceImports::MiyazakiSource::URL
    @pages = { "#{@root}/robots.txt" => "User-agent: *\nDisallow: /wp-admin/\n" }
    PlaceImports::MiyazakiClient::REVIEW.each do |review|
      @pages["#{@root}#{review.fetch('path')}"] = File.read(Rails.root.join("test/fixtures/files/place_imports/miyazaki/#{review.fetch('fixture')}.html"))
    end
    @client = Client.new(@pages)
    @source = PlaceImports::MiyazakiSource.new(client: @client)
  end

  test 'reviewed facts preserve current identity hours prices and qualifications' do
    data = @source.fetch(@url)
    assert_equal 'アイ・ホームテニスコート（生目の杜運動公園）', data['name']
    assert_equal '宮崎県宮崎市大字跡江4461番地1', data['address']
    assert_equal '0985-47-6222', data['tel']
    assert_equal ['テニス'], data['sports']
    assert_equal '2', data['tag']
    %w[9:00 22:00 水曜日 17:00].each { |s| assert_includes data['time'], s }
    ['第4水曜日', '翌日', '12月29日～1月3日'].each { |s| assert_includes data['regular_holiday'], s }
    ['16面', '屋外', 'ソフトテニス', '有料施設利用者のみ', '事務所で受付'].each { |s| assert_includes data['scale'], s }
    ['中学生以下240円', '高校生350円', '一般700円', '3,500円', '中学生以下480円', '高校生700円', '一般1,400円', '7,000円', '510円', '2,550円', '340円', '入場料を徴収する場合', '1面1時間'].each { |s| assert_includes data['price'], s }
    ['10:00～18:00', '土日祝', 'ソフトバンクホークスキャンプ', '100円', '200円', '自動二輪車以外'].each { |s| assert_includes data['parking'], s }
    ['車で約5分', '土日祝のみ', 'コート入口までの所要時間ではありません'].each { |s| assert_includes data['access'], s }
    assert_empty data['alerts']
    assert data['evidence'].any? { |e| e['text'].include?('１９時００分以降も利用可能') }
    assert_equal "#{@root}/robots.txt", @client.requests.first
  end

  test 'all reviewed facts and notices are protected including old outage recovery' do
    PlaceImports::MiyazakiClient::REVIEW.each do |review|
      url = "#{@root}#{review.fetch('path')}"
      original = @pages[url]
      @pages[url] = original.sub('</body>', '<p>新しい利用制限または料金資格条件</p></body>')
      assert_equal 'unreviewed_source_change', assert_raises(PlaceImports::MiyazakiSource::SourceError, url) { @source.fetch(@url) }.message
      @pages[url] = original
    end
  end

  test 'changed tariff values table spans links images and missing structure fail closed' do
    ['700円', 'rowspan="4"', 'facilities_img07.jpg', '跡江4461番地1', 'id="main"'].each do |value|
      original = @pages[@url]
      assert_includes original, value
      @pages[@url] = original.gsub(value, 'changed')
      assert_raises(PlaceImports::MiyazakiSource::SourceError, value) { @source.fetch(@url) }
      @pages[@url] = original
    end
    @pages["#{@root}/"].gsub!('href="https://ikimenomori.jp/', 'href="https://unreviewed.example/')
    assert_raises(PlaceImports::MiyazakiSource::SourceError) { @source.fetch(@url) }
    assert_not @client.requests.any? { |url| url.include?('unreviewed.example') }
  end

  test 'partial seed never claims citywide completion' do
    assert_equal [{ 'url' => @url }], @source.seeds
    assert_equal 'partial_reviewed_seed_only', assert_raises(PlaceImports::MiyazakiSource::SourceError) { @source.discover }.message
    assert_empty @client.requests
  end

  test 'robots is refreshed each fetch and can block every reviewed path' do
    @source.fetch(@url)
    @client.requests.clear
    @pages["#{@root}/robots.txt"] = "Disallow: /\n"
    assert_equal 'robots_disallowed', assert_raises(PlaceImports::MiyazakiSource::SourceError) { @source.fetch(@url) }.message
    assert_equal ["#{@root}/robots.txt"], @client.requests
    @pages["#{@root}/robots.txt"] = "Disallow: /facilities/*$\n"
    assert_raises(PlaceImports::MiyazakiSource::SourceError) { @source.fetch(@url) }
    assert_not @client.requests.include?(@url)
  end

  test 'client rejects unreviewed schemes hosts ports paths and credential fields before network' do
    client = PlaceImports::MiyazakiClient.new
    %w[http://ikimenomori.jp/ https://www.ikimenomori.jp/ https://ikimenomori.jp:444/ https://user@ikimenomori.jp/ https://ikimenomori.jp/?x=1 https://ikimenomori.jp/#x https://ikimenomori.jp/wp-admin/ https://ikimenomori.jp/unreviewed.pdf].each do |url|
      assert_raises(PlaceImports::OfficialClient::FetchError) { client.get(url) }
    end
  end

  test 'single candidate publishes once and keeps scheduler scope partial' do
    prepare_taxonomy
    runner = PlaceImports::NationwideRunner.new(source: @source)
    assert_no_difference('Place.count') { runner.call }
    assert_equal 'ready', PlaceImportCandidate.last.status
    assert_difference('Place.count', 1) { runner.call(apply: true) }
    assert_equal 'registered', PlaceImportCandidate.last.status
    assert_no_difference('Place.count') { runner.call(apply: true) }
    assert_equal false, runner.report[:complete]
    assert_equal 0, runner.report[:remaining]
  end

  test 'apply rechecks cached previews and holds changed fees notices or robots' do
    prepare_taxonomy
    runner = PlaceImports::NationwideRunner.new(source: @source)
    runner.call
    candidate = PlaceImportCandidate.last
    assert_equal 'ready', candidate.status
    @pages[@url].sub!('700円', '900円')
    assert_no_difference('Place.count') { runner.call(apply: true) }
    assert_equal 'pending', candidate.reload.status
    assert_equal 2, @client.requests.count(@url)
  end

  test 'apply rechecks robots for an already collected candidate' do
    prepare_taxonomy
    runner = PlaceImports::NationwideRunner.new(source: @source)
    runner.call
    candidate = PlaceImportCandidate.last
    candidate.update!(status: 'collected')
    @pages["#{@root}/robots.txt"] = "Disallow: /\n"
    @client.requests.clear
    assert_no_difference('Place.count') { runner.call(apply: true) }
    assert_equal 'pending', candidate.reload.status
    assert_equal ["#{@root}/robots.txt"], @client.requests
  end

  test 'changed source is held without publication or repeated attempts' do
    prepare_taxonomy
    @pages[@url].sub!('700円', '900円')
    runner = PlaceImports::NationwideRunner.new(source: @source)
    assert_no_difference('Place.count') { assert_equal 'completed', runner.call(apply: true).status }
    assert_equal 'pending', PlaceImportCandidate.last.status
    @client.requests.clear
    assert_no_difference('Place.count') { runner.call(apply: true) }
    assert_empty @client.requests
  end

  test 'known address duplicate is held and existing details stay untouched' do
    prepare_taxonomy
    existing = Place.create!(name: '生目の杜運動公園テニスコート', address: '宮崎県宮崎市大字跡江４４６１番地１', prefecture: @prefecture, city: @city, events: [@event], tag: '2', price: '既存の料金')
    assert_no_difference('Place.count') { PlaceImports::NationwideRunner.new(source: @source).call(apply: true) }
    assert_equal 'duplicate', PlaceImportCandidate.last.status
    assert_equal '既存の料金', existing.reload.price
  end

  private

  def prepare_taxonomy
    category = Category.create!(name: '球技', kana: 'miyazaki-ball', order: '1')
    @event = Event.create!(name: 'テニス', ruby: 'miyazaki-tennis', category: category, place: 1, order: '1')
    @prefecture = Prefecture.create!(name: '宮崎県', kana: 'miyazaki-test', order: '1')
    @city = City.create!(name: '宮崎市', city_kana: 'miyazaki-shi', prefecture: @prefecture)
  end
end
