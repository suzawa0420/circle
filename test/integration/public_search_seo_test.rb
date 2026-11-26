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
    @circle.update_columns(pic_header: 'test-cover.jpg')
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
      assert_select 'h1', text: "全1件#{subject}"
      unless path.start_with?('/categories/')
        first_image = css_select('img.header_imege_user_list[fetchpriority=high]').first
        assert_select 'link[rel=preload][as=image][type="image/webp"][fetchpriority=high][href=?]', first_image['src'], count: 1
      end
    end
  end

  test 'listing titles show filtered totals without year or unrelated conditions' do
    get @path
    assert_select 'title', text: '【全1件】東京都のバスケチーム募集 | サークルブック'
    assert_select 'h1', text: '全1件東京都のバスケチーム募集'
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
    assert_select 'h1', text: '全1件東京都の初心者歓迎のバドミントンサークル募集'
    other = Tag.create!(name: '50代', text: '50代の')
    get "/#{@circle.event.ruby}/#{@circle.prefecture.kana}/tag/#{other.id}"
    assert_response :success
    assert_select 'title', text: '【全0件】東京都の50代のバドミントンサークル募集 | サークルブック'
  end

  test 'only the clean Tokyo badminton listing has the tailored search snippet' do
    @circle.event.update!(name: 'バドミントン', txt: 'バドミントンサークル・クラブ', ruby: 'badminton')
    @circle.prefecture.update!(kana: 'tokyo')
    path = '/events/badminton/prefectures/tokyo'
    title = '東京都のバドミントンサークル募集｜初心者・社会人も探せる | サークルブック'
    description = '東京都で募集中のバドミントンサークルを検索。初心者・社会人・学生などの条件で絞り込み、活動場所・開催曜日・参加費を比べられます。'

    ['Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)'].each do |agent|
      get path, headers: { 'User-Agent' => agent }
      assert_response :success
      assert_select 'title', text: title
      assert_select 'meta[name=description][content=?]', description, count: 1
      assert_select 'link[rel=canonical][href=?]', "https://circle-book.com#{path}", count: 1
      assert_select 'meta[name=robots][content*=noindex]', count: 0
      assert_select 'h1', text: '全1件東京都のバドミントンサークル募集'
      assert_select ".user_item_wrap a[href='#{circle_path(@circle)}']"
      assert_select 'meta[name=listing-adsense]', count: 1
    end

    [{ sort: '2' }, { age: '1' }, { page: '1' }, { utm_source: 'test' }].each do |query|
      get path, params: query
      assert_response :success
      assert_select 'title', text: '【全1件】東京都のバドミントンサークル募集 | サークルブック'
      assert_select 'meta[name=description][content=?]', description, count: 0
      expected_canonical = "https://circle-book.com#{path}#{'?age=1' if query.key?(:age)}"
      assert_select 'link[rel=canonical][href=?]', expected_canonical, count: 1
    end

    Event.create!(name: 'バスケ', txt: 'バスケチーム', ruby: 'basketball', category: @circle.category, order: '2')
    city = City.create!(name: '世田谷区', city_kana: 'setagaya', prefecture: @circle.prefecture)
    UsersCity.create!(user: @circle, city: city)
    ['/events/badminton', "#{path}/cities/#{city.city_kana}", '/events/basketball/prefectures/tokyo', '/prefectures/tokyo', '/dates/badminton/tokyo'].each do |other|
      get other
      assert_response :success
      assert_select 'title', text: title, count: 0
      assert_select 'meta[name=description][content=?]', description, count: 0
    end

    total = User.list.page(1).limit_value + 1
    (total - 1).times do |i|
      User.create!(@circle.attributes.except('id', 'created_at', 'updated_at', 'unique_id').merge(name: "検索検証バドミントン#{i}"))
    end
    SearchResultCountCache::STORE.clear
    get path, params: { page: '2' }
    assert_response :success
    assert_select 'title', text: "【全#{total}件】東京都のバドミントンサークル募集（2ページ目） | サークルブック"
    assert_select 'meta[name=description][content=?]', description, count: 0
    assert_select 'link[rel=canonical][href=?]', "https://circle-book.com#{path}?page=2", count: 1
  end

  test 'circle list preserves full metadata without generating a placeholder cover' do
    name = '検索一覧で省略されても残る正式サークル名と活動場所の長い表示'
    @circle.update_columns(
      name: name, user_time: Date.new(2026, 10, 9), switch: '募集中', schedule: '毎週月曜',
      area: '世田谷区', sport_details: { experience: '未経験者も歓迎', equipment: '室内シューズ持参', meeting_area: '体育館受付集合' }
    )
    tag = Tag.create!(name: '社会人歓迎', text: '社会人歓迎の')
    UserTag.create!(user: @circle, tag: tag)
    @circle.reviews.create!(review: 1, comment: '楽しく活動できました。')
    3.times do |i|
      @circle.schedules.create!(day: (Date.current + i + 1).iso8601, title: "テスト活動#{i}", venue: "検証体育館#{i}")
    end

    get @path
    assert_response :success
    assert_select 'link[rel=preload][as=image]', count: 0
    assert_select '.cb-circle-list-card__cover', count: 0
    assert_select '.cb-circle-list-card__link[href=?][aria-label=?]', circle_path(@circle), name, count: 1
    assert_select '.cb-circle-list-card__name', text: name, count: 1
    assert_select 'time.cb-listing-card__date[datetime="2026-10-09"]', text: '2026年10月9日', count: 1
    assert_select '.cb-circle-list-card__badge', text: '募集中'
    %w[初心者歓迎 未経験者も歓迎 室内シューズ持参 体育館受付集合 一回５００円 ２０代中心 世田谷区 毎週月曜].each do |value|
      assert_select '.cb-circle-list-card', text: /#{value}/
    end
    assert_select '.cb-circle-list-card__rating .star > *', count: 5
    assert_select '.cb-circle-list-card__rating', text: /1件/
    assert_select '.cb-circle-list-card__tags a[href=?]', tag_path(tag), text: tag.name
    assert_select '.cb-circle-list-card__upcoming li', count: 2
    assert_select '.cb-circle-list-card__upcoming', text: /検証体育館0.*検証体育館1/m
  end

  test 'circle facts keep full schedule cost and age even when a small screen elides them' do
    schedule = '毎週日曜日の夕方に体育館で活動しています。' * 5
    cost = '参加費は会場によって異なります。' * 6
    age = '十代から幅広い年齢の参加者を歓迎します。' * 5
    @circle.update_columns(schedule: schedule, cost: cost, average_age: age, user_time: nil, switch: '')
    SearchResultCountCache::STORE.clear

    get @path
    assert_response :success
    assert_select '.cb-circle-list-card', count: 1 do
      assert_select '.cb-circle-list-card__cover, .cb-circle-list-card__status', count: 0
      assert_select '.cb-circle-list-card__facts .cb-circle-list-card__fact', count: 3
      [schedule, "参加費：#{cost}", "参加者の年代：#{age}"].each do |fact|
        assert_select '.cb-circle-list-card__facts .cb-circle-list-card__fact > span[title=?]', fact, text: fact
      end
    end
  end

  test 'similar circle cards keep the complete location and schedule in distinct fields' do
    area = '港区三田・' + '田町駅周辺の体育館' * 7
    schedule = '毎週土曜日の夕方から練習しています。' * 5
    related = @circle.dup
    related.assign_attributes(name: '地域のバスケサークル', area: area, schedule: schedule)
    related.save!

    get circle_path(@circle)
    assert_response :success
    assert_select '.cb-circle-list-card__related-list .cb-circle-list-card__link[href=?]', circle_path(related), count: 1 do
      location = "東京都・#{area}"
      assert_select '.cb-circle-list-card__fact--location', count: 1 do
        assert_select 'svg.cb-icon--map-pin', count: 1
        assert_select 'span[title=?]', location, text: location
      end
      assert_select '.cb-circle-list-card__fact--related-schedule', count: 1 do
        assert_select 'svg.cb-icon--calendar-days', count: 1
        assert_select 'span[title=?]', schedule, text: schedule
      end
      assert_select '.cb-circle-list-card__compact-arrow', count: 1
    end
  end

  test 'public landing page prioritizes first image and omits editing scripts' do
    @circle.update_columns(pic_header: 'test-cover.jpg')
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
    assert_select '[data-deferred-listing-ad], .admax-switch', count: 0
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
    assert_select 'h1', text: "全#{count + 1}件東京都のバスケチーム募集（2ページ目）"
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

  test 'primary and secondary regions retain their existing visibility rules' do
    secondary = Prefecture.create!(name: '神奈川県', kana: 'sitemap-kanagawa')
    invalid = Prefecture.create!(name: '非掲載地域', kana: 'nil')
    @circle.update_columns(prefecture_sub_id: secondary.id)
    @circle.dup.tap do |record|
      record.assign_attributes(name: '別の公開サークル', prefecture_sub_id: invalid.id)
      record.save!
    end
    event = @circle.event.ruby
    primary = @circle.prefecture.kana

    expected = ["/events/#{event}", "/events/#{event}/prefectures/#{primary}",
      "/events/#{event}/prefectures/#{secondary.kana}", "/prefectures/#{primary}"].sort
    assert_equal expected, CircleSitemapLandings.each_path.map { |path, _| path }.sort
    assert_equal [0.8], CircleSitemapLandings.each_path.map { |_, priority| priority }.uniq

    @owner.update_columns(check: AdminUser::SHADOW_BANNED_CHECK)
    assert_empty CircleSitemapLandings.each_path.to_a
  end

  test 'sitemap always emits an index and truthful canonical landings' do
    today = Time.current.in_time_zone('Tokyo').to_date
    @circle.schedules.create!(day: today.iso8601, title: '本日のバスケ', venue: '公開体育館')
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
      assert_includes urls, "https://circle-book.com#{EventDayListing.path(today)}"
      assert_includes urls, 'https://circle-book.com/dates/today'
      assert_includes urls, 'https://circle-book.com' + EventSearchPage.path(event: @circle.event.ruby, prefecture: @circle.prefecture.kana, period: 'today')
      assert_includes urls, 'https://circle-book.com' + EventSearchPage.path(event: @circle.event.ruby, prefecture: @circle.prefecture.kana)
      assert_includes urls, "https://circle-book.com#{user_schedule_path(@circle, @circle.schedules.first)}"
      refute urls.any? { |url| url.include?('?event=') || url.include?('&pref=') }
      refute urls.any? { |url| url.include?('/kw/') || url.include?('/search/') }
      landing = child.xpath('//url').find { |node| node.at_xpath('loc').text == "https://circle-book.com#{@path}" }
      assert_nil landing.at_xpath('lastmod')
    end
  ensure
    SitemapGenerator::Sitemap.public_path = previous_path if previous_path
    SitemapGenerator::Sitemap.reset!
  end

end
