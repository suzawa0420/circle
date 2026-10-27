require 'test_helper'
require_relative '../support/chat_records'

class CircleCitySearchTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    SearchResultCountCache::STORE.clear
    create_chat_records
    @prefecture = @circle.prefecture
    @city = City.create!(name: '渋谷区', city_kana: 'city-shibuya', prefecture: @prefecture)
    @empty_city = City.create!(name: '新宿区', city_kana: 'city-shinjuku', prefecture: @prefecture)
    @other_prefecture = Prefecture.create!(name: '神奈川県', kana: 'city-kanagawa')
    @other_city = City.create!(name: '横浜市', city_kana: 'city-yokohama', prefecture: @other_prefecture)
    UsersCity.create!(user: @circle, city: @city)
  end

  test 'city options depend on prefecture and stay single select without hidden duplicates' do
    get circles_path
    assert_select 'select[name=city_id][disabled]:not([multiple])', count: 1
    get prefecture_path(@prefecture.kana)
    assert_select 'select[name=city_id]:not([disabled]):not([multiple])', count: 1 do
      assert_select 'option[value=?]', @city.id.to_s
      assert_select 'option[value=?]', @empty_city.id.to_s
      assert_select 'option[value=?]', @other_city.id.to_s, count: 0
    end
    assert_select 'input[type=hidden][name=city_id]', count: 0
    get circles_search_cities_path, params: { prefecture_id: @prefecture.id }
    assert_response :success
    assert_equal 'noindex', response.headers['X-Robots-Tag']
    assert_equal [@city.id, @empty_city.id], response.parsed_body.map { |city| city['id'] }
    assert_raises(ActiveRecord::RecordNotFound) { get circles_search_cities_path, params: { prefecture_id: 0 } }
    assert_raises(ActiveRecord::RecordNotFound) { get circles_search_cities_path, params: { prefecture_id: [@prefecture.id] } }
  end

  test 'simple city filters redirect to existing canonical pages and preserve sort' do
    [{}, { event_id: @circle.event.id }].each do |extra|
      options = { detailed: '1', prefecture_id: @prefecture.id, city_id: @city.id, sort: '2' }.merge(extra)
      path = CircleCityDirectory.path(@city, event: extra.any? ? @circle.event : nil)
      get circles_search_index_path, params: options
      assert_redirected_to "#{path}?sort=2"
      follow_redirect!
      assert_response :success
      assert_select 'link[rel=canonical][href=?]', "https://circle-book.com#{path}"
      assert_select 'meta[name=robots][content*=noindex]', count: 0
      assert_select 'h1', text: /全1件東京都渋谷区/
      assert_select '.cb-search-city select[name=city_id] option[selected][value=?]', @city.id.to_s
      assert_select 'details select[name=city_id]', count: 0
      assert_select '.cb-sort a[href*=city_id]', count: 0
    end
  end

  test 'city plus keyword and age stays filtered noindex and removable' do
    # Registered cities may include activity areas beyond the primary prefecture.
    @circle.update!(prefecture: @other_prefecture)
    age = Age.create!(name: '20代', decade: 20)
    UsersAge.create!(user: @circle, age: age)
    get circles_search_index_path, params: { detailed: '1', q: 'サークル', prefecture_id: @prefecture.id,
      city_id: @city.id, age_ids: [age.id] }
    assert_response :success
    assert_select 'h1', text: /全1件東京都渋谷区の20代向け/
    assert_select 'meta[name=robots][content*=noindex]'
    assert_select '.cb-active-filters__item', text: /東京都/ do |links|
      query = Rack::Utils.parse_nested_query(URI(links.first['href']).query)
      refute query.key?('city_id')
      refute query.key?('prefecture_id')
      assert_equal [age.id.to_s], query['age_ids']
    end
    assert_select '.cb-active-filters__item', text: /渋谷区/ do |links|
      query = Rack::Utils.parse_nested_query(URI(links.first['href']).query)
      refute query.key?('city_id')
      assert_equal @prefecture.id.to_s, query['prefecture_id']
    end
  end

  test 'mismatched city and prefecture return 404 in canonical and detailed searches' do
    ['', 'サークル'].each do |keyword|
      assert_raises(ActiveRecord::RecordNotFound) do
        get circles_search_index_path, params: { detailed: '1', q: keyword,
          prefecture_id: @other_prefecture.id, city_id: @city.id }
      end
    end
    assert_raises(ActiveRecord::RecordNotFound) do
      get prefecture_city_path(@other_prefecture.kana, @city.city_kana)
    end
  end

  test 'only registered public circles create city landing pages and links' do
    all_path = CircleCityDirectory.path(@city)
    sport_path = CircleCityDirectory.path(@city, event: @circle.event)
    get prefecture_path(@prefecture.kana)
    assert_select '.cb-city-directory a[href=?]', all_path
    assert_select '.cb-city-directory a[href=?]', CircleCityDirectory.path(@empty_city), count: 0
    get event_prefecture_path(@circle.event.ruby, @prefecture.kana)
    assert_select '.cb-city-directory a[href=?]', sport_path
    urls = CircleCityDirectory.each_populated_path.to_a
    assert_includes urls, all_path
    assert_includes urls, sport_path
    refute_includes urls, CircleCityDirectory.path(@empty_city)
    assert_equal urls.uniq, urls
    @circle.update_columns(publication_status: 'draft')
    assert_empty CircleCityDirectory.each_populated_path.to_a
    get all_path
    assert_select 'meta[name=robots][content*=noindex]'
  end

  test 'nationwide results cannot populate unregistered cities and other sports stay excluded' do
    nationwide = Prefecture.find_by(id: 50) || Prefecture.create!(id: 50, name: '全国', kana: 'city-national')
    @circle.update!(prefecture: nationwide)
    get CircleCityDirectory.path(@empty_city)
    assert_select 'h1', text: /全0件/
    assert_select 'meta[name=robots][content*=noindex]'
    secondary = Event.create!(name: 'バドミントン', ruby: 'city-badminton', category: @circle.category)
    path = CircleCityDirectory.path(@city, event: secondary)
    refute_includes CircleCityDirectory.each_populated_path.to_a, path
    get path
    assert_response :success
    assert_select 'h1', text: /全0件東京都渋谷区のバドミントン/
  end
end
