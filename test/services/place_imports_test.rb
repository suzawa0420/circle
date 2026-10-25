require 'test_helper'

class PlaceImportsTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  setup do
    category = Category.create!(name: '球技', kana: 'import-ball', order: '1')
    @event = Event.create!(name: 'バスケ', ruby: 'import-basketball', category: category, place: 1, order: '1')
    @prefecture = Prefecture.create!(name: '東京都', kana: 'import-tokyo', order: '1')
    @city = City.create!(name: '世田谷区', city_kana: 'setagaya', prefecture_id: @prefecture.id)
    @data = { 'name' => '新しい体育館', 'address' => '東京都世田谷区尾山台3-19-3', 'prefecture' => '東京都', 'city' => '世田谷区',
      'access' => '駅から徒歩10分', 'parking' => 'なし', 'time' => '9:00～21:00',
      'regular_holiday' => '年末年始', 'scale' => 'バスケットボール1面', 'price' => '2時間3,000円',
      'tag' => '1', 'sports' => ['バスケットボール'], 'tel' => '03-1111-2222',
      'url' => 'https://www.se-sports.or.jp/facility/example/', 'alerts' => [],
      'evidence' => [{ 'url' => 'https://www.se-sports.or.jp/facilityinfo/example-gym/', 'label' => '体育館', 'text' => 'バスケットボール 1面' }] }
    @source = Struct.new(:key, :data) { def collect; data; end }.new('test_official', [@data])
  end

  test 'preview persists evidence without publishing and apply is idempotent including counters' do
    assert_no_difference('Place.count') { PlaceImports::Runner.new(source: @source).call }
    candidate = PlaceImportCandidate.last
    assert_equal '自動登録可能（プレビュー）', candidate.reason
    assert_equal @data['evidence'], candidate.payload['evidence']
    assert_difference('Place.count', 1) { PlaceImports::Runner.new(source: @source).call(apply: true) }
    assert_equal 'registered', candidate.reload.status
    assert_equal [@event.id], candidate.place.event_ids
    PlaceImports::Registrar::DETAIL_LABELS.each_key { |key| assert_equal @data[key], candidate.place.public_send(key) }
    assert_equal 1, @city.reload.places_count
    assert_equal 1, @prefecture.reload.places_count
    candidate.place.update!(price: '管理者が確認した料金')
    @data['price'] = '別の公式料金'
    assert_no_difference('Place.count') { PlaceImports::Runner.new(source: @source).call(apply: true) }
    assert_equal '管理者が確認した料金', candidate.place.reload.price
    candidate.place.destroy!
    assert_nil candidate.reload.place_id
    assert_no_difference('Place.count') { PlaceImports::Runner.new(source: @source).call(apply: true) }
  end

  test 'normalized address phone URL and similar names prevent duplicates' do
    %w[address tel url name].each do |key|
      place = Place.create!(name: '別施設', address: '東京都世田谷区別町9-9', prefecture: @prefecture, city: @city, events: [@event], tag: '1')
      attrs = { 'address' => '東京都世田谷区尾山台３丁目１９番３号', 'tel' => '0311112222',
        'url' => 'http://se-sports.or.jp/facility/example/?ref=test', 'name' => '新しい体育館（旧称）' }
      place.update!(key => attrs.fetch(key))
      candidate = build_candidate("duplicate-#{key}")
      assert_no_difference('Place.count') { assert_equal 'duplicate', PlaceImports::Registrar.new.call(candidate, apply: true) }
      place.destroy!
    end
  end

  test 'missing ambiguous stale closed and unsupported facilities remain pending' do
    [{ 'price' => nil }, { 'access' => '' }, { 'sports' => [] }, { 'tag' => nil }, { 'address' => '不明' }, { 'city' => '不明区' },
      { 'alerts' => ['改修工事に伴う休館'] }, { 'sports' => ['未対応種目'] }, { 'evidence' => [] }].each_with_index do |changes, index|
      candidate = build_candidate("invalid-#{index}", @data.merge(changes))
      assert_no_difference('Place.count') { assert_equal 'pending', PlaceImports::Registrar.new.call(candidate, apply: true) }
    end
    candidate = build_candidate('stale')
    candidate.update!(checked_at: 8.days.ago)
    assert_equal 'pending', PlaceImports::Registrar.new.call(candidate, apply: true)
  end

  test 'dismissal survives collection and actual insert cap ignores already registered candidates' do
    runner = PlaceImports::Runner.new(source: @source)
    runner.call(apply: true)
    second = @data.merge('name' => '二番目体育館', 'address' => '東京都世田谷区二町2-2', 'tel' => '03-3333-4444', 'url' => 'https://www.se-sports.or.jp/facility/two/')
    third = @data.merge('name' => '三番目体育館', 'address' => '東京都世田谷区三町3-3', 'tel' => '03-5555-6666', 'url' => 'https://www.se-sports.or.jp/facility/three/')
    @source.data += [second, third]
    assert_difference('Place.count', 1) { runner.call(apply: true, limit: 1) }
    candidate = PlaceImportCandidate.find_by(source_url: third['url'])
    assert_equal 'pending', candidate.status
    candidate.update!(status: 'dismissed')
    assert_no_difference('Place.count') { runner.call(apply: true) }
    assert_equal 'dismissed', candidate.reload.status
  end

  test 'failed collection is recorded without exception messages' do
    @source.define_singleton_method(:collect) { raise PlaceImports::OfficialClient::FetchError, 'private response body' }
    assert_raises(PlaceImports::OfficialClient::FetchError) { PlaceImports::Runner.new(source: @source).call }
    run = PlaceImportRun.last
    assert_equal 'failed', run.status
    assert_not_includes run.summary.to_json, 'private response body'
  end

  private

  def build_candidate(fingerprint, data = @data)
    run = PlaceImportRun.create!(source: 'test_official', mode: 'preview')
    PlaceImportCandidate.create!(source: run.source, source_url: data['url'], fingerprint: fingerprint, payload: data, checked_at: Time.current, place_import_run: run)
  end
end
