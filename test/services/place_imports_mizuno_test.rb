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

  test 'bare route text after bullet spans and unwrapped parking conditions survive extraction' do
    @pages["#{@url}/access"].sub!(/<div class="show_body_access">.*<\/div><\/main>/, <<~HTML)
      <div class="show_body_access"><h3>車でご来場の場合</h3>
      <span>●</span>近隣の駐車場：<a href="https://example.test/parking">公園駐車場</a><br>
      <span>●</span>収容可能台数：32台（専用ではありません）<br>
      ・最初の30分無料、以降30分100円<br>・最大料金なし<br>
      ※サービス券の発行はありません。<br>
      <h3>電車でご来場の場合</h3>
      <span>●</span>阪急千里線：吹田駅・豊津駅（徒歩8分）<br>
      <span>●</span>JR東海道本線：吹田駅（徒歩15分）<br>
      <h3>その他</h3>別項目</div></main>
    HTML
    data = PlaceImports::MizunoSource.new(client: Client.new(@pages)).fetch(@url)
    assert_equal "電車でご来場の場合\n●阪急千里線：吹田駅・豊津駅（徒歩8分）\n●JR東海道本線：吹田駅（徒歩15分）", data['access']
    assert_includes data['parking'], '収容可能台数：32台（専用ではありません）'
    assert_includes data['parking'], '・最大料金なし'
    assert_includes data['parking'], '※サービス券の発行はありません。'
    assert_not_includes data['access'], '別項目'
  end

  test 'heading and empty bullet markers alone leave access unconfirmed' do
    @pages["#{@url}/access"].sub!(/<div class="show_body_access">.*<\/div><\/main>/,
      '<div class="show_body_access"><h3>電車でご来場の場合</h3><span>●</span><br><span>●</span></div></main>')
    assert_nil PlaceImports::MizunoSource.new(client: Client.new(@pages)).fetch(@url)['access']
  end

  test 'unwrapped rate notes after inline elements are retained' do
    @pages["#{@url}/guide"] = '<div class="show_body_guide"><h3>体育館利用料金</h3><span>●</span>利用資格：登録団体<br><table><tr><td>1時間</td><td>1000円</td></tr></table><span>※</span>市外利用者は2倍です。<br>夜間は別途500円が必要です。<h3>その他</h3>別施設の情報</div>'
    price = PlaceImports::MizunoSource.new(client: Client.new(@pages)).fetch(@url)['price']
    assert_includes price, '利用資格：登録団体'
    assert_includes price, '市外利用者は2倍です。'
    assert_includes price, '夜間は別途500円が必要です。'
    assert_not_includes price, '別施設の情報'
  end

  test 'separate air conditioning tariffs retain the following numbered conditions' do
    @pages["#{@url}/guide"] = '<div class="show_body_guide"><h3>専用利用</h3><table><tr><td>体育館・1時間</td><td>3000円 ※1</td></tr></table><h3>冷暖房利用 ※5</h3><table><tr><td>利用者の要望による場合・1時間</td><td>1800円</td></tr></table><p>※1 税込料金です。照明料金は利用料金に含みます。</p><p>※5 健康を害さない程度の空調は利用料に含みます。</p></div>'
    price = PlaceImports::MizunoSource.new(client: Client.new(@pages)).fetch(@url)['price']
    assert_includes price, '冷暖房利用 ※5'
    assert_includes price, '利用者の要望による場合・1時間 | 1800円'
    assert_includes price, '照明料金は利用料金に含みます'
    assert_includes price, '健康を害さない程度の空調は利用料に含みます'
  end

  test 'facility tariffs and court named fallback sections retain notes outside tables' do
    @pages["#{@url}/guide"] = '<div class="show_body_guide"><h3>体育施設利用料【税込み】</h3><table><tr><td>体育館</td><td>1000円</td></tr></table><p>※付帯設備の半額減免はありません。</p></div>'
    assert_includes PlaceImports::MizunoSource.new(client: Client.new(@pages)).fetch(@url)['price'], '※付帯設備の半額減免はありません。'
    @pages["#{@url}/guide"] = '<div class="show_body_guide"><h2>メインアリーナ</h2><table><tr><th>1時間</th><th>市内</th></tr><tr><td>全面</td><td>1000円</td></tr></table><p>※営利目的は基本使用料の20割を加算。</p><p>※1時間未満の端数は1時間として計算します。</p><h2>サブアリーナ</h2><table><tr><td>1時間</td><td>500円</td></tr></table><p>※2分割利用可。使用割合を乗じます。</p></div>'
    price = PlaceImports::MizunoSource.new(client: Client.new(@pages)).fetch(@url)['price']
    assert_includes price, '営利目的は基本使用料の20割を加算'
    assert_includes price, '1時間未満の端数は1時間として計算'
    assert_includes price, '2分割利用可。使用割合を乗じます'
    assert_equal 1, price.scan('営利目的は').length
  end

  test 'ancillary tariffs are retained with court rates but cannot substitute for them' do
    ancillary = '<h2>その他施設</h2><table><tr><td>会議室</td><td>500円</td></tr></table><p>※冷暖房は3割加算。</p>'
    @pages["#{@url}/guide"] = '<div class="show_body_guide">' + ancillary + '</div>'
    assert_nil PlaceImports::MizunoSource.new(client: Client.new(@pages)).fetch(@url)['price']
    @pages["#{@url}/guide"] = '<div class="show_body_guide"><h2>メインアリーナ</h2><table><tr><td>1時間</td><td>1000円</td></tr></table>' + ancillary + '</div>'
    price = PlaceImports::MizunoSource.new(client: Client.new(@pages)).fetch(@url)['price']
    assert_includes price, '会議室 | 500円'
    assert_includes price, '※冷暖房は3割加算。'
  end

  test 'separate reduction conditions supplement a confirmed court tariff' do
    @pages["#{@url}/guide"] = '<div class="show_body_guide"><h2>減免利用</h2><p>事前申請と通知書の提示により5割減免。</p><h2>メインアリーナ</h2><table><tr><td>1時間</td><td>1000円</td></tr></table></div>'
    price = PlaceImports::MizunoSource.new(client: Client.new(@pages)).fetch(@url)['price']
    assert_includes price, '事前申請と通知書の提示により5割減免。'
  end

  test 'individual rates with a yen caption do not need a currency suffix in every cell' do
    @pages["#{@url}/guide"] = '<div class="show_body_guide"><h2>利用料金（占用利用）</h2><table><caption>単位：円、1時間</caption><tr><td>体育館</td><td>6,300</td></tr></table><h2>利用料金：個人利用</h2><table><caption>単位：円</caption><tr><th>施設</th><th>区分</th><th>1時間あたり</th></tr><tr><td>サブアリーナ</td><td>中学生以下</td><td>各150</td></tr><tr><td>サブアリーナ</td><td>大人</td><td>各300</td></tr></table><p>中学生以下は保護者同伴。</p></div>'
    price = PlaceImports::MizunoSource.new(client: Client.new(@pages)).fetch(@url)['price']
    assert_includes price, '体育館 | 6,300'
    assert_includes price, '利用料金：個人利用'
    assert_includes price, 'サブアリーナ | 中学生以下 | 各150'
    assert_includes price, 'サブアリーナ | 大人 | 各300'
    assert_includes price, '中学生以下は保護者同伴'
  end

  test 'nested official editor wrappers do not repeat the following tariff' do
    @pages["#{@url}/guide"] = '<div class="show_body_guide"><h2>利用料金（占用利用）</h2><div><table><tr><td>全面</td><td>1000円</td></tr></table><h2>利用料金：個人利用</h2><table><caption>単位：円</caption><tr><td>大人</td><td>300</td></tr></table></div></div>'
    price = PlaceImports::MizunoSource.new(client: Client.new(@pages)).fetch(@url)['price']
    assert_equal 1, price.scan('利用料金：個人利用').length
    assert_equal 1, price.scan('大人 | 300').length
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
