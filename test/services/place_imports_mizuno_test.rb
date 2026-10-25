require 'test_helper'
require 'minitest/mock'

class PlaceImportsMizunoTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  class Client
    attr_reader :requests
    def initialize(pages); @pages, @requests = pages, []; end
    def get(url); @requests << url; @pages.fetch(url); end
  end

  setup do
    @url = 'https://shisetsu.mizuno.jp/m-test'
    @pages = {
      'https://shisetsu.mizuno.jp/robots.txt' => "User-agent: *\nDisallow:",
      @url => '<a href="/m-test/news/page/1">通常のお知らせ</a>',
      "#{@url}/access" => '<main><section class="facility_info_section"><div class="info_wrap"><p class="name">テスト体育館</p><span class="address">大阪府吹田市1-2-3</span><span class="tel"><a>06-1111-2222</a></span></div></section><div class="show_body_access"><h4>駐車場について</h4><p>20台・無料</p><h4>電車・バスでご来場の場合</h4><p>駅から徒歩5分</p></div></main>',
      "#{@url}/guide" => '<main><table id="facility_use_tbl"><tr><th>営業時間</th><td>9:00～21:00</td></tr><tr><th>休館日</th><td>月曜日</td></tr></table><div class="show_body_guide"><h3>体育館専用利用料金</h3><table><tr><th>区分</th><th>1時間</th></tr><tr><td>全面</td><td>1000円</td></tr></table></div></main>',
      "#{@url}/gallery" => '<main><div class="inline-wrap"><div class="txt_wrap"><p class="top_header">メインアリーナ</p><p>体育館400㎡<br>バスケットボール1面<br>バドミントン2面</p></div></div><div class="inline-wrap"><div class="txt_wrap"><p class="top_header">屋外テニスコート</p><p>テニス2面</p></div></div></main>'
    }
  end

  test 'collects six facts for the indoor gym without including adjacent outdoor sports' do
    data = PlaceImports::MizunoSource.new(client: Client.new(@pages)).fetch(@url)
    assert_equal '大阪府', data['prefecture']
    assert_equal '1', data['tag']
    assert_equal ['バスケットボール', 'バドミントン'], data['sports']
    assert_includes data['access'], '徒歩5分'
    assert_includes data['parking'], '20台'
    assert_includes data['price'], '全面 | 1000円'
    assert_includes data['price'], "#{@url}/guide"
    assert_equal '月曜日', data['regular_holiday']
    assert_not_includes data['scale'], 'テニス'
  end

  test 'image-only rates remain unconfirmed and permanent closure notices are retained' do
    @pages["#{@url}/guide"] = '<div class="show_body_guide"><h3>体育館利用料金</h3><img src="/rates.jpg"></div>'
    @pages[@url] = '<a href="/m-test/news/page/2">体育館閉館のお知らせ</a>'
    data = PlaceImports::MizunoSource.new(client: Client.new(@pages)).fetch(@url)
    assert_nil data['price']
    assert_equal ['体育館閉館のお知らせ'], data['alerts']
  end

  test 'court descriptions without numeric counts remain valid while prohibitions do not create sports' do
    @pages["#{@url}/gallery"] = '<main><div class="inline-wrap"><div class="txt_wrap"><p class="top_header">第1体育室</p><p>施設面積400㎡。団体利用：バスケットボール・バレーボール等の練習が可能です。バドミントンは利用できません。</p></div></div></main>'
    data = PlaceImports::MizunoSource.new(client: Client.new(@pages)).fetch(@url)
    assert_equal ['バスケットボール', 'バレーボール'], data['sports']
  end

  test 'mixed indoor and outdoor tennis facilities stay unclassified' do
    @pages["#{@url}/access"].sub!('テスト体育館', 'テストスポーツガーデン')
    @pages["#{@url}/gallery"] = '<main><div class="inline-wrap"><div class="txt_wrap"><p class="top_header">インドアテニスコート</p><p>屋根あり2面</p></div></div><div class="inline-wrap"><div class="txt_wrap"><p class="top_header">アウトドアテニスコート</p><p>6面</p></div></div></main>'
    assert_nil PlaceImports::MizunoSource.new(client: Client.new(@pages)).fetch(@url)['tag']
  end

  test 'rate conditions before and after tables are retained and training-only fees are rejected' do
    @pages["#{@url}/guide"] = '<div class="show_body_guide"><h3>ご利用料金</h3><p>【専用使用】市外団体は10割増しです。</p><table><tr><th>体育室</th><th>午前</th></tr><tr><td>全面</td><td>1000円</td></tr></table><p>【個人使用】市外利用者は2倍です。</p><table><tr><th>区分</th><th>1回</th></tr><tr><td>一般</td><td>300円</td></tr></table></div>'
    price = PlaceImports::MizunoSource.new(client: Client.new(@pages)).fetch(@url)['price']
    assert_includes price, '市外団体は10割増し'
    assert_includes price, '市外利用者は2倍'
    @pages["#{@url}/guide"] = '<div class="show_body_guide"><h3>トレーニング講習のご利用方法</h3><table><tr><td>受講料</td><td>150円</td></tr><tr><td>備考</td><td>他の体育館でも利用できます</td></tr></table></div>'
    assert_nil PlaceImports::MizunoSource.new(client: Client.new(@pages)).fetch(@url)['price']
  end

  test 'multi-facility operator names are not silently classified as indoor' do
    @pages["#{@url}/access"].sub!('テスト体育館', '体育館等｜総合運動公園')
    assert_nil PlaceImports::MizunoSource.new(client: Client.new(@pages)).fetch(@url)['tag']
  end

  test 'table captions preserve tariff units and eligibility' do
    @pages["#{@url}/guide"] = '<div class="show_body_guide"><h2>利用料金（占用利用）</h2><table><caption>アマチュア・入場料なし（1時間）単位:円</caption><tr><th>施設</th><th>平日</th></tr><tr><td>体育館</td><td>6,300</td></tr></table><p>市外は1.5倍、入場料1000円以上は2倍。</p></div>'
    price = PlaceImports::MizunoSource.new(client: Client.new(@pages)).fetch(@url)['price']
    assert_includes price, 'アマチュア・入場料なし（1時間）単位:円'
    assert_includes price, '体育館 | 6,300'
    assert_includes price, '市外は1.5倍'
  end

  test 'directory discovery rejects empty maintenance and follows only approved pagination' do
    directory = PlaceImports::MizunoSource::DIRECTORY
    @pages['https://sports-service.mizuno.jp/robots.txt'] = ''
    @pages[directory] = "<a href='#{@url}'>施設</a><a href='https://evil.test/m-other'>外部</a><a rel='next' href='?page=2'>次へ</a>"
    @pages[directory + '?page=2'] = "<a href='#{@url}-two'>施設2</a>"
    source = PlaceImports::MizunoSource.new(client: Client.new(@pages))
    assert_equal [@url, @url + '-two'], source.discover.map { |item| item['url'] }
    @pages[directory] = '<h1>メンテナンス中です</h1>'
    assert_raises(PlaceImports::MizunoSource::SourceError) { PlaceImports::MizunoSource.new(client: Client.new(@pages)).discover }
  end

  test 'new client rejects unrelated hosts ports credentials and queries before network access' do
    client = PlaceImports::MizunoClient.new(interval: 0)
    ['https://127.0.0.1/m-test', 'http://shisetsu.mizuno.jp/m-test', 'https://shisetsu.mizuno.jp:444/m-test',
      'https://user:password@shisetsu.mizuno.jp/m-test', 'https://shisetsu.mizuno.jp/m-test?token=test',
      'https://sports-service.mizuno.jp/search/?page=2&secret=x'].each do |url|
      assert_raises(PlaceImports::OfficialClient::FetchError) { client.get(url) }
    end
  end
end
