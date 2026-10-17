require 'test_helper'
require_relative '../support/chat_records'

class CircleAudienceDiscoveryTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    Rails.cache.clear
    SearchResultCountCache::STORE.clear
    create_chat_records
    @circle.update!(recruitment: '初参加も歓迎します')
    @group = Group.create!(name: '社会人')
    @age = Age.create!(name: '20代', decade: 20)
    UsersGroup.create!(user: @circle, group: @group)
    UsersAge.create!(user: @circle, age: @age)
  end

  def landing(group: nil, age: nil)
    CircleFilterLanding.path(event: @circle.event, prefecture: @circle.prefecture, group: group, age: age)
  end

  test 'parent links to populated audiences and fixed pages keep activity area and selected audience' do
    get event_prefecture_path(@circle.event.ruby, @circle.prefecture.kana)
    assert_select '.cb-audience-directory a[href=?]', landing(group: @group)
    assert_select '.cb-audience-directory a[href=?]', landing(age: @age)
    get landing(group: @group)
    assert_select '.cb-audience-directory a[href=?]', landing(group: @group, age: @age)
    assert_select '.cb-audience-directory a[href=?]', landing(age: @age), count: 0
    get landing(age: @age)
    assert_select '.cb-audience-directory a[href=?]', landing(group: @group, age: @age)
    get landing(group: @group, age: @age)
    assert_response :success
    assert_select 'meta[name=robots][content*=noindex]', count: 0
    assert_select '.cb-audience-directory', count: 0
    assert_select '.cb-discovery p', text: /活動場所・日程・参加費/
  end

  test 'closed draft and other area circles cannot create empty discovery links' do
    @circle.update!(switch: '受付終了')
    get prefecture_path(@circle.prefecture.kana)
    assert_select '.cb-audience-directory', count: 0
    @circle.update_columns(switch: '募集中', publication_status: 'draft')
    get prefecture_path(@circle.prefecture.kana)
    assert_select '.cb-audience-directory', count: 0
    @circle.update_columns(publication_status: 'published')
    other = Prefecture.create!(name: '神奈川県', kana: 'audience-kanagawa')
    get prefecture_path(other.kana)
    assert_select '.cb-audience-directory', count: 0
  end

  test 'fixed audience breadcrumbs link to the matching parents and expose the same structured trail' do
    get landing(group: @group, age: @age)
    assert_select '.breadcrumbs a[href=?]', event_prefecture_path(@circle.event.ruby, @circle.prefecture.kana)
    assert_select '.breadcrumbs a[href=?]', landing(group: @group), text: '社会人向けの募集'
    assert_select '.breadcrumbs [aria-current=page]', text: '社会人・20代向けの募集', count: 1
    assert_select '.breadcrumbs', text: /「」/, count: 0
    nodes = css_select('script[type="application/ld+json"]').map { |node| JSON.parse(node.text) }
    trail = nodes.find { |node| node['@type'] == 'BreadcrumbList' }.fetch('itemListElement')
    assert_equal '社会人・20代向けの募集', trail.last['name']
    assert_equal "https://circle-book.com#{landing(group: @group)}", trail[-2]['item']
  end

  test 'city and keyword listings never link to broader audiences as if filters were preserved' do
    city = City.create!(name: '渋谷区', city_kana: 'audience-shibuya', prefecture: @circle.prefecture)
    UsersCity.create!(user: @circle, city: city)
    get CircleCityDirectory.path(city)
    assert_select '.cb-audience-directory', count: 0
    get circles_search_index_path, params: { detailed: '1', q: 'サークル', age_ids: [@age.id] }
    assert_select '.cb-audience-directory', count: 0
  end

  test 'legacy age tag keeps canonical and membership while offering explicit audience alternative' do
    tag = Tag.create!(name: '20代', text: '20代を募集中の')
    UserTag.create!(user: @circle, tag: tag)
    path = "/#{@circle.event.ruby}/#{@circle.prefecture.kana}/tag/#{tag.id}"
    get path
    assert_response :success
    assert_select 'link[rel=canonical][href=?]', "https://circle-book.com#{path}"
    assert_select 'meta[name=description][content*="20代"]'
    assert_select '.cb-audience-directory a[href=?]', landing(group: @group, age: @age)
    UsersAge.where(user_id: @circle.id).delete_all
    get path
    assert_select '.cb-audience-directory', count: 0
    assert_select 'h1', text: /全1件/
  end

  test 'regional discovery includes populated tennis camping and cafe genres without empty or hidden sports' do
    helper = Object.new.extend(SportDiscoveryHelper)
    %w[tennis camping gathering].each do |slug|
      event = Event.create!(name: '検証種目', ruby: slug, txt: '検証サークル', category: @circle.category)
      @circle.update!(event: event)
      assert_includes helper.region_discovery_sports(@circle.prefecture), event
      get event_prefecture_path(event.ruby, @circle.prefecture.kana)
      assert_select '.cb-discovery p', text: /#{Regexp.escape(SportDiscoveryHelper::SPORT_GUIDES.fetch(slug))}/
      @circle.update_columns(publication_status: 'draft')
      refute_includes helper.region_discovery_sports(@circle.prefecture), event
      @circle.update_columns(publication_status: 'published')
    end
  end

  test 'audience navigation only appears on first page and uses canonical paths without sort' do
    get prefecture_path(@circle.prefecture.kana), params: { sort: '2' }
    assert_select '.cb-audience-directory a' do |links|
      assert links.any?
      links.each { |link| refute_includes link['href'], '?' }
    end
    get prefecture_path(@circle.prefecture.kana), params: { page: '1' }
    assert_select '.cb-audience-directory', count: 1
  end
end
