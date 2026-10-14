require 'test_helper'

class PlacesDirectoryTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    category = Category.create!(name: '球技', kana: 'places-ball', order: '1')
    @basketball = Event.create!(name: 'バスケ', ruby: 'places-basketball', category: category, place: 1, order: '1')
    @tennis = Event.create!(name: 'テニス', ruby: 'places-tennis', category: category, place: 1, order: '2')
    @tokyo = Prefecture.create!(name: '東京都', kana: 'places-tokyo', order: '1')
    @osaka = Prefecture.create!(name: '大阪府', kana: 'places-osaka', order: '2')
    @city = City.create!(name: '目黒区', city_kana: 'meguro', prefecture_id: @tokyo.id)
    other_city = City.create!(name: '大阪市', city_kana: 'osaka', prefecture_id: @osaka.id)
    @gym = facility('中央体育館', @tokyo, @city, @basketball)
    @park = facility('中央テニスコート', @tokyo, @city, @tennis)
    @other = facility('中央大阪体育館', @osaka, other_city, @basketball)
  end

  test 'top has sport and area search, bounded summaries and working facility links' do
    get '/places'
    assert_response :success
    assert_select 'form[action="/places/search"] select[name=sport] option', count: 3
    assert_select 'select[name=area] option', count: 3
    assert_select '.place-card', count: 3
    assert_select '.place-card h2 a', text: @gym.name, href: path_for(@gym)
    assert_select '.place-card-fact dd' do |summaries|
      assert summaries.all? { |summary| summary.text.length <= 90 }
    end
    assert_not_includes response.body, '<script>alert'
    get path_for(@gym)
    assert_response :success
    assert_includes response.body, '最終料金'
  end

  test 'combined filters preserve selected values and use AND for keywords' do
    get '/places/search', params: { sport: @basketball.ruby, area: @tokyo.kana, kw: '中央　目黒区' }
    assert_response :success
    assert_select 'meta[name=robots][content=noindex]'
    assert_select '.place-card', count: 1
    assert_select '.place-card h2 a', text: @gym.name
    assert_select 'select[name=sport] option[selected]', text: @basketball.name
    assert_select 'select[name=area] option[selected]', text: @tokyo.name
    assert_select 'input[name=kw][value="中央　目黒区"]'
    get '/places/search', params: { kw: '中央 大阪府' }
    assert_select '.place-card', count: 1
    assert_select '.place-card h2 a', text: @other.name
  end

  test 'sport keyword searches stay within the sport and match city names' do
    get "/places/#{@basketball.ruby}/search", params: { kw: '目黒区' }
    assert_response :success
    assert_select '.place-card', count: 1
    assert_select '.place-card h2 a', text: @gym.name
  end

  test 'empty results and malformed keyword parameters render safely' do
    get '/places/search', params: { kw: '存在しない施設' }
    assert_response :success
    assert_select '.place-card', count: 0
    assert_select '.sorry_message', text: '該当する体育館・コートがありません'
    get '/places/search', params: { kw: ['中央'] }
    assert_response :success
    get '/places/search', params: { kw: '%' }
    assert_select '.place-card', count: 0
    assert_raises(ActiveRecord::RecordNotFound) do
      get '/places/search', params: { sport: 'unknown-sport' }
    end
  end

  test 'sport prefecture and city pages share the compact cards' do
    ["/places/#{@basketball.ruby}", "/places/#{@basketball.ruby}/#{@tokyo.kana}", "/places/#{@basketball.ruby}/#{@tokyo.kana}/#{@city.city_kana}"].each do |path|
      get path
      assert_response :success
      assert_select '.places-directory .place-card'
      assert_select '.place-card-footer a.places-action', text: '詳細を確認する'
    end
  end

  test 'pagination retains the search conditions' do
    11.times { |index| facility("中央体育館#{index}", @tokyo, @city, @basketball) }
    get '/places/search', params: { sport: @basketball.ruby, area: @tokyo.kana, kw: '中央', page: 2 }
    assert_response :success
    assert_select '.place-card', count: 2
    assert_select '.pagination a' do |links|
      links.each do |link|
        query = Rack::Utils.parse_nested_query(URI.parse(link['href']).query)
        assert_equal @basketball.ruby, query['sport']
        assert_equal @tokyo.kana, query['area']
        assert_equal '中央', query['kw']
      end
    end
  end

  private

  def facility(name, prefecture, city, event)
    Place.create!(name: name, prefecture: prefecture, city: city, events: [event], tag: '1', address: '駅前1-2-3',
                  access: '駅から徒歩5分', time: '9:00〜21:00', price: "<script>alert('x')</script>" + '一般料金1時間500円。' * 30 + '最終料金')
  end

  def path_for(place)
    "/places/#{place.events.first.ruby}/#{place.prefecture.kana}/#{place.city.city_kana}/#{place.id}"
  end
end
