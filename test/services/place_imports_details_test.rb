require 'test_helper'

class PlaceImportsDetailsTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  setup do
    @document = Nokogiri::HTML(<<~HTML)
      <dl>
        <div class="c-summaryTable__item"><dt>開館時間</dt><dd>9:00～21:00<br>曜日による</dd></div>
        <div class="c-summaryTable__item"><dt>休館日</dt><dd>12月29日～1月3日</dd></div>
        <div class="c-summaryTable__item"><dt>駐車場</dt><dd>なし</dd></div>
        <div class="c-summaryTable__item"><dt>利用資格</dt><dd>登録団体</dd></div>
      </dl>
      <div class="p-facility-singleTab__accessPublicItem">
        <p class="p-facility-singleTab__accessPublicItemPoint"><span class="p-facility-singleTab__accessPublicItemPoint2">駅</span></p>
        <p class="p-facility-singleTab__accessPublicItemMeans">バス5分</p>
        <p class="p-facility-singleTab__accessPublicItemPoint"><span class="p-facility-singleTab__accessPublicItemPoint2">バス停</span></p>
        <p class="p-facility-singleTab__accessPublicItemUntilArrival">徒歩2分</p>
      </div>
      <footer>事務局駐車場：100台、別施設は24時間営業</footer>
    HTML
    @facility = { label: '体育館', url: 'https://www.se-sports.or.jp/facilityinfo/test-gym/', document: Nokogiri::HTML(<<~HTML) }
      <main><h2>基本情報</h2><p>フローリング410㎡<br>バレーボール1面</p>
        <ul class="useTab"><li>個人利用</li><li>団体利用</li></ul>
        <div class="useTabpanel_contents person"><div><h2>利用料金</h2>
          <table><tr><th>対象</th><th>1教室</th></tr><tr><td>大人</td><td>160円</td></tr></table>
          <p>幼児は無料</p><h2>利用上の注意</h2><p>個人利用の注意事項</p>
        </div></div>
        <div class="useTabpanel_contents group"><div><h2>利用時間及び利用料金</h2>
          <table><tr><th>利用時間</th><th>水曜</th><th>木曜</th></tr>
          <tr><td>13:30～16:00</td><td>1,010円</td><td>－</td></tr></table>
          <h2>利用上の注意</h2><p>団体利用の注意事項</p>
        </div></div>
      </main>
    HTML
  end

  test 'collects access summary and rates with individual and group contexts' do
    data = PlaceImports::SetagayaDetails.new.call(@document, [@facility])
    assert_equal '駅 → バス5分 → バス停 → 徒歩2分', data['access']
    assert_equal 'なし', data['parking']
    assert_equal "9:00～21:00\n曜日による", data['time']
    assert_equal '12月29日～1月3日', data['regular_holiday']
    assert_equal "体育館\nフローリング410㎡\nバレーボール1面", data['scale']
    assert_includes data['price'], "体育館\n個人利用\n対象 | 1教室\n大人 | 160円"
    assert_includes data['price'], "体育館\n団体利用\n利用時間 | 水曜 | 木曜\n13:30～16:00 | 1,010円 | －"
    assert_includes data['price'], '登録団体'
    assert_includes data['price'], @facility[:url]
    assert_not_includes data.values.join, '注意事項'
    assert_not_includes data.values.join, '100台'
  end

  test 'merged rate headers retain each weekday and half or full court distinction' do
    @facility[:document] = Nokogiri::HTML(<<~HTML)
      <h2>利用料金</h2><table>
      <tr><th rowspan="2">時間</th><th colspan="2">平日</th><th colspan="2">休日</th></tr>
      <tr><th>半面</th><th>全面</th><th>半面</th><th>全面</th></tr>
      <tr><td>9:00～12:00</td><td>100円</td><td>200円</td><td>300円</td><td>400円</td></tr>
      </table><h2>注意</h2>
    HTML
    price = PlaceImports::SetagayaDetails.new.call(@document, [@facility])['price']
    assert_includes price, '時間 | 平日 | 平日 | 休日 | 休日'
    assert_includes price, '時間 | 半面 | 全面 | 半面 | 全面'
    assert_includes price, '9:00～12:00 | 100円 | 200円 | 300円 | 400円'
  end

  test 'unknown details remain blank and a link alone is not a confirmed rate' do
    @facility[:document] = Nokogiri::HTML('<h2>利用料金</h2><p><a href="/other">こちらをご覧ください</a></p>')
    data = PlaceImports::SetagayaDetails.new.call(Nokogiri::HTML('<footer>駐車場あり</footer>'), [@facility])
    PlaceImports::Registrar::DETAIL_LABELS.each_key { |key| assert_nil data[key] }
  end
end
