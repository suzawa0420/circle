require 'test_helper'

class PlaceImportsSendaiTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  class Client
    attr_reader :requests
    def initialize(pages); @pages, @requests = pages, []; end
    def get(url); @requests << url; @pages.fetch(url); end
  end

  setup do
    @url = PlaceImports::SendaiSource::URL
    @pages = { "#{@url}robots.txt" => "User-agent: *\nDisallow: /wp-admin/\n" }
    { '' => 'home', 'shisetsu/' => 'shisetsu', 'access/' => 'access', 'charge/' => 'charge', 'yoyaku/' => 'yoyaku' }.each do |path, file|
      @pages["#{@url}#{path}"] = File.read(Rails.root.join("test/fixtures/files/place_imports/sendai/#{file}.html"))
    end
    @client = Client.new(@pages)
    @source = PlaceImports::SendaiSource.new(client: @client)
  end

  test 'extracts reviewed operator details and preserves all tariff qualifications' do
    data = @source.fetch(@url)
    assert_equal '出花体育館', data['name']
    assert_equal '宮城県仙台市宮城野区出花一丁目13−7', data['address']
    assert_nil data['city']
    assert_equal '1', data['tag']
    assert_equal '022-786-3446', data['tel']
    assert_equal '9:00～21:00', data['time']
    assert_includes data['access'], '中野栄駅下車'
    assert_includes data['parking'], '一般41台・車いす専用1台・車いす優先4台'
    assert_includes data['regular_holiday'], '不定期'
    assert_equal %w[バスケットボール バレーボール バドミントン 卓球], data['sports']
    assert_includes data['scale'], '32m×24m'
    assert_includes data['price'], '入場料なし | 非営利 | 2,400 | 3,200 | 4,800'
    assert_includes data['price'], '入場料徴収 | 営利 | 12,200 | 16,200 | 24,400'
    assert_includes data['price'], '土曜・日曜・祝日'
    assert_includes data['price'], '2割増'
    assert_includes data['price'], '1/2'
    assert_includes data['price'], '小学生・中学生 | 120円'
    assert_includes data['price'], '使用料／回'
    assert_includes data['price'], '障がい者手帳'
    assert_includes data['price'], '高校生以上：240円'
    assert_empty data['alerts']
    assert_equal "#{@url}robots.txt", @client.requests.first
  end

  test 'missing tariff qualifications fail closed' do
    @pages["#{@url}charge/"].gsub!('2割増', '')
    assert_raises(PlaceImports::SendaiSource::SourceError) { @source.fetch(@url) }
  end

  test 'partial seeds never masquerade as complete discovery' do
    assert_equal [{ 'url' => @url }], @source.seeds
    assert_raises(PlaceImports::SendaiSource::SourceError) { @source.discover }
    assert_empty @client.requests
  end

  test 'robots is checked before any facility request' do
    @pages["#{@url}robots.txt"] = "User-agent: *\nDisallow: /\n"
    assert_raises(PlaceImports::SendaiSource::SourceError) { @source.fetch(@url) }
    assert_equal ["#{@url}robots.txt"], @client.requests
  end

  test 'PDF only prices remain missing and missing content is rejected' do
    @pages["#{@url}charge/"] = '<div id="rightCo"><a href="fee.pdf">料金表</a></div>'
    assert_nil @source.fetch(@url)['price']
    @pages["#{@url}charge/"] = '<h1>maintenance</h1>'
    assert_raises(PlaceImports::SendaiSource::SourceError) { @source.fetch(@url) }
  end

  test 'closure alerts are preserved and missing access is not invented' do
    @pages[@url].sub!('</h1>', '</h1><div>改修工事により利用休止</div>')
    @pages["#{@url}access/"].gsub!('公共交通機関', '交通案内未確認')
    data = @source.fetch(@url)
    assert_includes data['alerts'], '改修工事により利用休止'
    assert_nil data['access']
  end

  test 'nonstandard sport names do not count as standard sports' do
    %w[ソフト ショート バウンド].each do |prefix|
      original = @pages["#{@url}shisetsu/"]
      @pages["#{@url}shisetsu/"] = original.gsub('テニスコート1面', "#{prefix}テニスコート1面").gsub('バレーボール2面', 'ソフトバレーボール2面')
      sports = @source.fetch(@url)['sports']
      assert_not_includes sports, 'テニス'
      assert_not_includes sports, 'バレーボール'
      @pages["#{@url}shisetsu/"] = original
    end
    @pages["#{@url}shisetsu/"].gsub!('テニスコート1面', 'テニスコート１面')
    @pages[@url].gsub!('ソフトテニス', '硬式テニス')
    assert_includes @source.fetch(@url)['sports'], 'テニス'
  end

  test 'homepage soft tennis evidence overrides generic court label' do
    data = @source.fetch(@url)
    assert_not_includes data['sports'], 'テニス'
    assert_includes data['scale'], '施設表記：テニスコート1面'
    assert_includes data['scale'], 'ソフトテニス'
    assert_includes data['scale'], '硬式テニスの利用可否は未確認'
    assert_includes data['evidence'].first['text'], 'ソフトテニス'
    @pages[@url].gsub!('利用可能な種目', 'changed heading')
    assert_raises(PlaceImports::SendaiSource::SourceError) { @source.fetch(@url) }
  end

  test 'unlinked table notices are retained and changed news structures fail closed' do
    @pages[@url].sub!('</h1>', '</h1><table><tr><td>競技場を臨時休館します</td></tr></table>')
    assert_includes @source.fetch(@url)['alerts'], '競技場を臨時休館します'
    @pages[@url].gsub!('newsINDEX', 'newLayout')
    assert_raises(PlaceImports::SendaiSource::SourceError) { @source.fetch(@url) }
  end

  test 'booking eligibility and concession removals fail closed' do
    original = @pages["#{@url}yoyaku/"]
    ['ank02', '予約', '利用可能日'].each do |label|
      @pages["#{@url}yoyaku/"] = original.gsub(label, '')
      assert_raises(PlaceImports::SendaiSource::SourceError) { @source.fetch(@url) }
    end
    @pages["#{@url}yoyaku/"] = original
    @pages["#{@url}shisetsu/"].gsub!('障がい者手帳', '')
    assert_raises(PlaceImports::SendaiSource::SourceError) { @source.fetch(@url) }
  end

  test 'client rejects unreviewed hosts paths queries and fragments before network' do
    client = PlaceImports::SendaiClient.new
    %w[http://ideka.spf-sendai.com/ https://www.city.sendai.jp/ https://ideka.spf-sendai.com/wp-admin/ https://ideka.spf-sendai.com/charge/?x=1 https://ideka.spf-sendai.com/charge/#x https://evil.example/].each do |url|
      assert_raises(PlaceImports::OfficialClient::FetchError) { client.get(url) }
    end
    assert_equal 2.megabytes, PlaceImports::SendaiClient::MAX_BYTES
  end
end
