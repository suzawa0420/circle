require 'test_helper'
require_relative '../support/chat_records'

class PublicSearchSeoTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords
  setup do
    create_chat_records
    @circle.update!(cost: '一回５００円', average_age: '２０代中心')
    @path = event_prefecture_path(@circle.event.ruby, @circle.prefecture.kana)
  end

  test 'public landing page prioritizes first image and omits editing scripts' do
    get @path, params: { sort: '3', page: '1', utm_source: 'test', gclid: 'test' }
    assert_response :success
    assert_select 'link[rel=canonical][href=?]', "https://circle-book.com#{@path}"
    assert_select 'meta[name=robots][content*=noindex]', count: 0
    assert_select 'script[src*=public_listing][defer]', count: 1
    assert_select 'script[src*=jquery-ui]', count: 0
    assert_select 'script[src*=application-]', count: 0
    assert_select 'img.header_imege_user_list[loading=eager][fetchpriority=high]', count: 1
    assert_select '.user_item_wrap', text: /一回５００円/
    assert_select '.user_item_wrap', text: /２０代中心/
    json = css_select('script[type="application/ld+json"]').map { |node| JSON.parse(node.text) }.find { |item| item['@type'] == 'ItemList' }
    assert_equal "https://circle-book.com#{circle_path(@circle)}", json['itemListElement'].first['url']
    assert_equal 1, json['itemListElement'].first['position']
  end

  test 'pagination retains canonical page and absolute structured positions' do
    count = User.list.page(1).limit_value
    count.times do |i|
      User.create!(@circle.attributes.except('id', 'created_at', 'updated_at', 'unique_id').merge(name: "検索検証サークル#{i}"))
    end
    get @path, params: { page: '2', sort: '3' }
    assert_response :success
    assert_select 'link[rel=canonical][href=?]', "https://circle-book.com#{@path}?page=2"
    json = css_select('script[type="application/ld+json"]').map { |node| JSON.parse(node.text) }.find { |item| item['@type'] == 'ItemList' }
    assert_equal count + 1, json['itemListElement'].first['position']
  end

  test 'invalid filters and empty deep pages are not found' do
    [{ sort: '9' }, { page: '-1' }, { page: 'abc' }, { page: '99999' }].each do |query|
      assert_raises(ActiveRecord::RecordNotFound) { get @path, params: query }
    end
    assert_raises(ActiveRecord::RecordNotFound) { get '/events/missing/prefectures/missing' }
    other = Prefecture.create!(name: '大阪府', kana: 'seo-osaka', order: '2', sort: 2)
    city = City.create!(name: '大阪市', city_kana: 'seo-osaka-city', prefecture: other)
    assert_raises(ActiveRecord::RecordNotFound) { get "#{@path}/cities/#{city.city_kana}" }
  end

  test 'empty valid landing and calendar pages are noindex' do
    @circle.update_columns(publication_status: 'draft')
    get @path
    assert_response :success
    assert_select 'meta[name=robots][content*=noindex]'
    get '/dates/2026/10/1'
    assert_response :success
    assert_select 'meta[name=robots][content*=noindex]'
  end

  test 'internal search is noindex without blocking links' do
    DbKeyword.create!(keyword: '検証サークル')
    get circles_search_path('検証サークル')
    assert_response :success
    assert_select 'meta[name=robots][content*=noindex]'
    assert_select 'meta[name=robots][content*=nofollow]', count: 0
  end
  test 'search landings with existing traffic remain indexable when populated' do
    query = '50代 散歩 東京'
    assert SearchLandingPolicy.indexable?(query)
    DbKeyword.create!(keyword: query)
    @circle.update!(name: '50代 散歩 東京サークル')
    get circles_search_path(query)
    assert_response :success
    assert_select 'meta[name=robots][content*=noindex]', count: 0
  end

  test 'sitemap always emits an index and truthful canonical landings' do
    require 'sitemap_generator'
    require 'aws-sdk-s3'
    require 'minitest/mock'
    require 'tmpdir'
    require 'zlib'
    previous_path = SitemapGenerator::Sitemap.public_path
    Dir.mktmpdir('circle-seo-sitemap') do |directory|
      SitemapGenerator::Sitemap.public_path = directory
      SitemapGenerator::AwsSdkAdapter.stub(:new, SitemapGenerator::FileAdapter.new) do
        SitemapGenerator::Interpreter.run
      end
      index = Nokogiri::XML(Zlib::GzipReader.open(File.join(directory, 'sitemaps/sitemap.xml.gz'), &:read))
      assert_equal 'sitemapindex', index.root.name
      child = Nokogiri::XML(Zlib::GzipReader.open(File.join(directory, 'sitemaps/sitemap1.xml.gz'), &:read)).remove_namespaces!
      urls = child.xpath('//url/loc').map(&:text)
      assert_includes urls, "https://circle-book.com#{@path}"
      assert_includes urls, "https://circle-book.com#{circle_path(@circle)}"
      refute urls.any? { |url| url.include?('/kw/') || url.include?('/search/') }
      landing = child.xpath('//url').find { |node| node.at_xpath('loc').text == "https://circle-book.com#{@path}" }
      assert_nil landing.at_xpath('lastmod')
    end
  ensure
    SitemapGenerator::Sitemap.public_path = previous_path if previous_path
    SitemapGenerator::Sitemap.reset!
  end

end
