require 'test_helper'
require_relative '../support/chat_records'

class PublicSearchSeoTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords
  setup do
    SearchResultCountCache::STORE.clear
    create_chat_records
    @circle.event.update!(txt: 'バスケチーム')
    @circle.update!(cost: '一回５００円', average_age: '２０代中心', recruitment: '初心者歓迎')
    @path = event_prefecture_path(@circle.event.ruby, @circle.prefecture.kana)
  end

  test 'national regional city category and tag listings share title conventions' do
    event = @circle.event.ruby
    prefecture = @circle.prefecture.kana
    category = @circle.category
    category.update!(txt: '球技のサークル・チーム')
    city = City.create!(name: '世田谷区', city_kana: 'title-setagaya', prefecture: @circle.prefecture)
    UsersCity.create!(user: @circle, city: city)
    tag = Tag.create!(name: '社会人サークル', text: '社会人の')
    UserTag.create!(user: @circle, tag: tag)
    paths = {
      '/circles' => 'サークル・チーム募集',
      "/events/#{event}" => 'バスケチーム募集',
      "/prefectures/#{prefecture}" => '東京都のサークル・チーム募集',
      "/prefectures/#{prefecture}/cities/#{city.city_kana}" => '東京都世田谷区のサークル・チーム募集',
      "#{@path}/cities/#{city.city_kana}" => '東京都世田谷区のバスケチーム募集',
      "/tags/#{tag.id}" => '社会人のサークル・チーム募集',
      "/#{event}/tag/#{tag.id}" => '社会人のバスケチーム募集',
      "/#{event}/#{prefecture}/#{city.city_kana}/tag/#{tag.id}" => '東京都世田谷区の社会人のバスケチーム募集',
      "/prefectures/#{prefecture}/tag/#{tag.id}" => '東京都の社会人のサークル・チーム募集',
      "/prefectures/#{prefecture}/#{city.city_kana}/tag/#{tag.id}" => '東京都世田谷区の社会人のサークル・チーム募集',
      "/categories/#{category.kana}" => '球技のサークル・チーム募集',
      "/categories/#{category.kana}/#{prefecture}" => '東京都の球技のサークル・チーム募集'
    }
    paths.each do |path, subject|
      get path
      assert_response :success
      assert_select 'title', text: "【全1件】#{subject} | サークルブック"
      assert_select 'h1', text: "【全1件】#{subject}"
      unless path.start_with?('/categories/')
        first_image = css_select('img.header_imege_user_list[fetchpriority=high]').first
        assert_select 'link[rel=preload][as=image][type="image/webp"][fetchpriority=high][href=?]', first_image['src'], count: 1
      end
    end
  end

  test 'listing titles show filtered totals without year or unrelated conditions' do
    get @path
    assert_select 'title', text: '【全1件】東京都のバスケチーム募集 | サークルブック'
    assert_select 'h1', text: '【全1件】東京都のバスケチーム募集'
    assert_select '.mobile-site-heading source[sizes="150px"][srcset*="320w"]', count: 1
    @circle.update_columns(publication_status: 'draft')
    SearchResultCountCache::STORE.clear
    get @path
    assert_select 'title', text: '【全0件】東京都のバスケチーム募集 | サークルブック'
    assert_select 'link[rel=preload][as=image]', count: 0
  end

  test 'genre and tag conditions distinguish titles and keep counts filtered' do
    tag = Tag.create!(name: '初心者歓迎', text: '初心者歓迎の')
    UserTag.create!(user: @circle, tag: tag)
    UserTag.create!(user: @circle, tag: tag)
    @circle.event.update!(name: 'バドミントン', txt: 'バドミントンサークル・クラブ')
    @circle.update!(prefecture_sub: @circle.prefecture)
    get "/#{@circle.event.ruby}/#{@circle.prefecture.kana}/tag/#{tag.id}"
    assert_response :success
    assert_select 'title', text: '【全1件】東京都の初心者歓迎のバドミントンサークル募集 | サークルブック'
    assert_select 'h1', text: '【全1件】東京都の初心者歓迎のバドミントンサークル募集'
    other = Tag.create!(name: '50代', text: '50代の')
    get "/#{@circle.event.ruby}/#{@circle.prefecture.kana}/tag/#{other.id}"
    assert_response :success
    assert_select 'title', text: '【全0件】東京都の50代のバドミントンサークル募集 | サークルブック'
  end

  test 'public landing page prioritizes first image and omits editing scripts' do
    get @path, params: { sort: '3', page: '1', utm_source: 'test', gclid: 'test' }
    assert_response :success
    assert_select 'link[rel=canonical][href=?]', "https://circle-book.com#{@path}"
    assert_select 'meta[name=robots][content*=noindex]', count: 0
    assert_select 'script[src*=public_listing][defer]', count: 1
    assert_select 'link[rel=stylesheet][href*=public_listing]', count: 1
    assert_select 'link[rel=stylesheet][href*=application-]', count: 0
    assert_select 'meta[name=listing-adsense]', count: 1
    assert_select 'script[src*=adsbygoogle]', count: 0
    assert_select 'script', text: /GTM-MD88D9HB/
    assert_select 'script[src*=jquery-ui]', count: 0
    assert_select '[data-deferred-listing-ad] .admax-switch', count: 1
    assert_select 'script[src="https://adm.shinobi.jp/st/t.js"]', count: 0
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
    assert_select 'title', text: "【全#{count + 1}件】東京都のバスケチーム募集（2ページ目） | サークルブック"
    assert_select 'h1', text: "【全#{count + 1}件】東京都のバスケチーム募集（2ページ目）"
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
