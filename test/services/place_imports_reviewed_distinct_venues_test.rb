require 'test_helper'

class PlaceImportsReviewedDistinctVenuesTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  setup do
    category = Category.create!(name: '球技', kana: 'distinct-ball', order: '1')
    @event = Event.create!(name: 'テニス', ruby: 'distinct-tennis', category: category, place: 1, order: '1')
    @prefecture = Prefecture.create!(name: '高知県', kana: 'distinct-kochi', order: '1')
    @city = City.create!(name: '高知市', city_kana: 'kochishi', prefecture: @prefecture)
    @existing = PlaceImports::ReviewedDistinctVenues::INDOOR_VENUES.map do |name, address|
      Place.create!(name: name, address: address, prefecture: @prefecture, city: @city,
        tag: '1', tel: '088-878-1150', events: [@event])
    end
    @data = {
      'name' => '東部総合運動場テニスコート', 'address' => '高知県高知市介良1221-1',
      'prefecture' => '高知県', 'city' => nil, 'tag' => '2', 'sports' => ['テニス'],
      'tel' => '088-878-1150', 'url' => PlaceImports::ReviewedDistinctVenues::URL,
      'access' => '親公園：高知駅から車で15分', 'parking' => '130台', 'time' => '日の出～21:00',
      'regular_holiday' => '12/29～1/3', 'scale' => '砂入り人工芝16面',
      'price' => '試験用の確認済み料金', 'alerts' => [], 'evidence' => [{ 'text' => '公式の施設別案内' }]
    }
  end

  test 'only the two reviewed indoor venues may share a reservation telephone' do
    candidate = build_candidate
    assert_difference('Place.count', 1) do
      assert_equal 'registered', PlaceImports::Registrar.new.call(candidate, apply: true)
    end
    assert_equal '088-878-1150', candidate.reload.place.tel
    assert_equal '2', candidate.place.tag
    @existing.each do |place|
      assert_equal '1', place.reload.tag
      assert_equal '088-878-1150', place.tel
    end
    assert_no_difference('Place.count') { PlaceImports::Registrar.new.call(candidate, apply: true) }
    another = build_candidate(fingerprint: 'repeat')
    assert_no_difference('Place.count') do
      assert_equal 'duplicate', PlaceImports::Registrar.new.call(another, apply: true)
    end
  end

  test 'a candidate cannot opt into the exception using IDs or changed identity' do
    [{ 'name' => '別の庭球場' }, { 'address' => '高知県高知市介良1221-2' },
      { 'tag' => '1' }, { 'sports' => ['テニス', '卓球'] },
      { 'url' => 'https://www.kc-sports.or.jp/facilities/unknown/' }].each_with_index do |change, index|
      data = @data.merge(change).merge('distinct_from_place_ids' => @existing.map(&:id))
      candidate = build_candidate(data: data, fingerprint: "changed-#{index}")
      assert_no_difference('Place.count') do
        assert_equal 'duplicate', PlaceImports::Registrar.new.call(candidate, apply: true)
      end
    end
    %w[unknown mizuno_nationwide].each do |source|
      candidate = build_candidate(source: source, fingerprint: source)
      assert_equal 'duplicate', PlaceImports::Registrar.new.call(candidate, apply: true)
    end
    candidate = build_candidate(source_url: 'https://www.kc-sports.or.jp/facilities/unknown/', fingerprint: 'source-url')
    assert_equal 'duplicate', PlaceImports::Registrar.new.call(candidate, apply: true)
  end

  test 'name address and URL matches always remain duplicates' do
    original = @existing.first.attributes.slice('name', 'address', 'url')
    %w[name address url].each do |key|
      @existing.first.update!(key => @data.fetch(key))
      candidate = build_candidate(fingerprint: "same-#{key}")
      assert_equal 'duplicate', PlaceImports::Registrar.new.call(candidate, apply: true)
      @existing.first.update!(original)
    end
  end

  test 'changed or additional shared contact venues still require review' do
    existing = @existing.first
    original = existing.attributes.slice('name', 'address', 'tag')
    { 'name' => 'くろしおアリーナ別館', 'address' => '高知県高知市五台山999', 'tag' => '2' }.each do |key, value|
      existing.update!(key => value)
      assert_equal 'duplicate', PlaceImports::Registrar.new.call(build_candidate(fingerprint: "other-#{key}"), apply: true)
      existing.update!(original)
    end
    Place.create!(name: '未審査の別施設', address: '高知県高知市別町5', prefecture: @prefecture, city: @city,
      tag: '1', tel: '088-878-1150', events: [@event])
    assert_equal 'duplicate', PlaceImports::Registrar.new.call(build_candidate(fingerprint: 'additional'), apply: true)
  end

  private

  def build_candidate(data: @data, source: 'kochi_sports', source_url: data['url'], fingerprint: 'reviewed')
    run = PlaceImportRun.create!(source: source, mode: 'preview')
    PlaceImportCandidate.create!(source: source, source_url: source_url, fingerprint: fingerprint,
      payload: data, checked_at: Time.current, place_import_run: run)
  end
end
