require 'test_helper'
require_relative '../support/chat_records'

class CircleFilterLandingsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    Rails.cache.clear
    SearchResultCountCache::STORE.clear
    create_chat_records
    @group = Group.create!(name: '初心者')
    @age = Age.create!(name: '60代以上', decade: 60)
    UsersGroup.create!(user: @circle, group: @group)
    UsersAge.create!(user: @circle, age: @age)
    @path = CircleFilterLanding.path(event: @circle.event, prefecture: @circle.prefecture, group: @group, age: @age)
  end

  test 'fixed populated page is indexable with matching titles and one selected form' do
    get @path
    assert_response :success
    subject = '東京都の初心者／60代以上向けのバスケサークル募集'
    assert_select 'h1', text: "全1件#{subject}"
    assert_select 'title', text: "【全1件】#{subject} | サークルブック"
    assert_select 'meta[name=description][content*=初心者]'
    assert_select 'link[rel=canonical][href=?]', "https://circle-book.com#{@path}"
    assert_select 'meta[name=robots][content*=noindex]', count: 0
    assert_select 'input[name="group_ids[]"][checked]', count: 1
    assert_select 'input[name="age_ids[]"][checked]', count: 1
    assert_select 'select[name=event_id] option[selected][value=?]', @circle.event.id.to_s
    assert_select 'select[name=prefecture_id] option[selected][value=?]', @circle.prefecture.id.to_s
  end

  test 'zero result landings stay usable but become noindex and leave sitemap candidates' do
    @circle.update_columns(publication_status: 'draft')
    get @path
    assert_response :success
    assert_select 'h1', text: /全0件/
    assert_select 'meta[name=robots][content*=noindex]'
    assert_select 'meta[name=robots][content*=nofollow]', count: 0
    refute_includes CircleFilterLanding.each_populated_path.to_a, @path
    assert_raises(ActiveRecord::RecordNotFound) { get @path, params: { page: '2' } }
  end

  test 'single select redirects to stable URL and duplicates normalize' do
    get circles_search_index_path, params: { detailed: '1', event_id: @circle.event.id, prefecture_id: @circle.prefecture.id,
      group_ids: [@group.id, @group.id], age_ids: [@age.id], sort: '2' }
    assert_redirected_to "#{@path}?sort=2"
    follow_redirect!
    assert_response :success
    assert_select 'link[rel=canonical][href=?]', "https://circle-book.com#{@path}"
    assert_select '.cb-sort [aria-current=true]', text: '人気順'
    get circle_filter_landing_path(activity: @circle.event.ruby, region: @circle.prefecture.kana, group: 'all', age: 'all')
    assert_redirected_to event_prefecture_path(@circle.event.ruby, @circle.prefecture.kana)
  end

  test 'multi-select and keywords stay noindex and cannot override fixed path' do
    other = Group.create!(name: '経験者')
    get circles_search_index_path, params: { detailed: '1', group_ids: [@group.id, other.id], age_ids: [@age.id] }
    assert_response :success
    assert_select 'meta[name=robots][content*=noindex]'
    assert_select 'h1', text: /初心者・経験者／60代以上/
    get circles_search_index_path, params: { detailed: '1', q: 'サークル', group_ids: [@group.id] }
    assert_response :success
    assert_select 'meta[name=robots][content*=noindex]'
    get @path, params: { group_ids: [other.id], q: '別条件', sort: '3' }
    assert_redirected_to "#{@path}?sort=3"
    assert_raises(ActiveRecord::RecordNotFound) do
      get circle_filter_landing_path(activity: 'not-an-event', region: 'all', group: @group.id, age: 'all')
    end
  end

  test 'registered combinations generate only populated paths without duplicate filter navigation' do
    sub = Prefecture.create!(name: '神奈川県', kana: 'landing-kanagawa')
    @circle.update!(prefecture_sub: sub)
    urls = CircleFilterLanding.each_populated_path.to_a
    assert_equal urls.uniq, urls
    assert_includes urls, @path
    assert_includes urls, CircleFilterLanding.path(event: @circle.event, prefecture: sub, group: @group, age: @age)
    assert_includes urls, CircleFilterLanding.path(group: @group)
    assert_includes urls, CircleFilterLanding.path(age: @age)
    get event_prefecture_path(@circle.event.ruby, @circle.prefecture.kana)
    assert_select '.cb-filter-landings', count: 0
    assert_select 'details.cb-detailed-search', count: 1
    get CircleFilterLanding.path(event: @circle.event, prefecture: @circle.prefecture, group: @group)
    assert_select '.cb-filter-landings', count: 0
    assert_select 'details.cb-detailed-search', count: 1
    urls.each do |url|
      get url
      assert_response :success
      assert_select 'meta[name=robots][content*=noindex]', count: 0
    end
  end

  test 'pagination and sorting do not leak hidden form filters into fixed URLs' do
    count = User.list.page(1).limit_value
    count.times do |i|
      circle = User.create!(@circle.attributes.except('id', 'created_at', 'updated_at', 'unique_id').merge(name: "固定URL検証#{i}"))
      UsersGroup.create!(user: circle, group: @group)
      UsersAge.create!(user: circle, age: @age)
    end
    get @path, params: { sort: '2' }
    assert_select '.pagination a[href*=page]' do |links|
      links.each do |link|
        refute_match(/detailed|group_ids|age_ids|event_id|prefecture_id/, link['href'])
      end
    end
    get @path, params: { page: '2', sort: '3' }
    assert_response :success
    assert_select 'link[rel=canonical][href=?]', "https://circle-book.com#{@path}?page=2"
    assert_select 'meta[name=robots][content*=noindex]', count: 0
  end

  test 'sitemap XML includes populated fixed pages and excludes empty ones' do
    require 'sitemap_generator'
    require 'aws-sdk-s3'
    require 'minitest/mock'
    require 'tmpdir'
    require 'zlib'
    other = Group.create!(name: '経験者')
    empty_path = CircleFilterLanding.path(group: other, age: @age)
    previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Rails.cache.write('published-sitemap-v2/sitemap', 'old index')
    Rails.cache.write('published-sitemap-v2/sitemap1', 'old child')
    Rails.cache.write('unrelated-cache-check', 'preserved')
    previous_path = SitemapGenerator::Sitemap.public_path
    Dir.mktmpdir('circle-filter-sitemap') do |directory|
      SitemapGenerator::Sitemap.public_path = directory
      SitemapGenerator::AwsSdkAdapter.stub(:new, SitemapGenerator::FileAdapter.new) do
        SitemapGenerator::Interpreter.run
      end
      xml = Nokogiri::XML(Zlib::GzipReader.open(File.join(directory, 'sitemaps/sitemap1.xml.gz'), &:read)).remove_namespaces!
      urls = xml.xpath('//url/loc').map(&:text)
      assert_nil Rails.cache.read('published-sitemap-v2/sitemap')
      assert_nil Rails.cache.read('published-sitemap-v2/sitemap1')
      assert_equal 'preserved', Rails.cache.read('unrelated-cache-check')
      assert_includes urls, "https://circle-book.com#{@path}"
      refute_includes urls, "https://circle-book.com#{empty_path}"
      refute urls.any? { |url| url.include?('?') }
    end
  ensure
    SitemapGenerator::Sitemap.public_path = previous_path if previous_path
    Rails.cache = previous_cache if previous_cache
    SitemapGenerator::Sitemap.reset!
  end

end
