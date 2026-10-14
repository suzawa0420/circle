require 'test_helper'
require_relative '../support/chat_records'

class EventSearchLandingsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    travel_to Time.zone.local(2026, 10, 14, 12)
    create_chat_records
    @circle.event.update!(ruby: 'basketball')
    @circle.prefecture.update!(name: '神奈川県', kana: 'kanagawa')
    @schedule = @circle.schedules.create!(day: Date.current.iso8601, title: '夜の練習会',
      venue: '公開体育館', cost: '500円', time_s: '18:00', time_e: '21:00',
      member_venue: '非公開会場', venue_address: '非公開住所')
    @base = '/dates/basketball/kanagawa'
  end

  teardown { travel_back }

  test 'genres regions and their combinations return unique upcoming landing pages' do
    {
      '/dates/basketball' => '全国のバスケイベント・練習会一覧',
      '/dates/prefectures/kanagawa' => '神奈川県のイベント・体験会一覧',
      @base => '神奈川県のバスケイベント・練習会一覧'
    }.each do |path, title|
      get path
      assert_response :success
      assert_select 'h1', text: title
      assert_select 'title', text: "#{title} | サークルブック"
      assert_select 'link[rel=canonical][href=?]', 'https://circle-book.com' + path
      assert_select 'meta[name=robots][content*=noindex]', count: 0
      assert_select '.event-results__card', count: 1
      assert_select '.event-results__text p', text: '参加費：500円'
      assert_select 'h1', text: /チーム募集|サークル募集/, count: 0
      assert_select '.event-results__discovery'
      assert_not_includes response.body, '非公開会場'
      assert_not_includes response.body, '非公開住所'
    end
    get @base
    assert_select '.event-results__discovery', text: /バスケットボール.*初心者.*一人参加/m
    assert_select 'a[href=?]', event_prefecture_path('basketball', 'kanagawa')
    data = structured_graph
    assert_equal %w[BreadcrumbList ItemList], data.map { |item| item['@type'] }
    assert_equal "https://circle-book.com#{user_schedule_path(@circle, @schedule)}", data.last['itemListElement'].first['url']
    assert_equal 'https://circle-book.com' + @base, data.first['itemListElement'].last['item']
  end

  test 'legacy filter URLs redirect once and preserve page sort and attribution' do
    20.times { |i| @circle.schedules.create!(day: Date.current.iso8601, title: "追加#{i}", venue: '公開体育館') }
    ['/dates', '/dates/today', '/dates/2026/10/14', '/dates/this_week'].each do |old|
      suffix = { '/dates' => '', '/dates/today' => '/today', '/dates/2026/10/14' => '/2026/10/14', '/dates/this_week' => '/this_week' }.fetch(old)
      get old, params: { event: 'basketball', pref: 'kanagawa', sort: '3', page: '2', utm_source: 'test' }
      target = @base + suffix
      assert_response :moved_permanently
      assert_redirected_to target + '?' + { page: '2', sort: '3', utm_source: 'test' }.to_query
      follow_redirect!
      assert_response :success
      assert_select 'link[rel=canonical][href=?]', 'https://circle-book.com' + target + '?page=2'
      assert_select 'meta[name=robots][content*=noindex]'
      assert_select 'h1', text: /2ページ目/
      assert_select '.event-results__discovery', count: 0
      assert_equal 21, structured_graph.last['itemListElement'].first['position']
    end
  end

  test 'all period routes work for genre region and combination without ambiguity' do
    ['/dates/basketball', '/dates/prefectures/kanagawa', @base].each do |base|
      %w[today tomorrow this_week next_week].each do |period|
        get base + '/' + period
        assert_response :success
        assert_select 'link[rel=canonical][href=?]', 'https://circle-book.com' + base + '/' + period
      end
      get base + '/2026/10/14'
      assert_response :success
    end
    get @base + '/today'
    assert_select 'a[href=?]', @base + '/tomorrow'
    assert_select 'form[action="/dates/today"]'
    get '/dates/today', params: { event: 'basketball', pref: 'kanagawa' }
    assert_redirected_to @base + '/today'
  end

  test 'empty past unknown and hidden listings do not become indexable pages' do
    get @base + '/2026/10/13'
    assert_select 'meta[name=robots][content*=noindex]'
    @circle.schedules.create!(day: '2026-10-13', title: '過去のイベント', venue: '公開体育館')
    get @base + '/2026/10/13'
    assert_select '.event-results__card', count: 1
    assert_select 'meta[name=robots][content*=noindex]'
    ['/dates/missing', '/dates/basketball/missing', @base + '/2026/2/30'].each do |path|
      assert_raises(ActiveRecord::RecordNotFound) { get path }
    end
    assert_raises(ActiveRecord::RecordNotFound) { get @base, params: { page: 'abc' } }
    assert_raises(ActiveRecord::RecordNotFound) { get @base, params: { page: 2 } }
    @circle.update_columns(publication_status: 'draft')
    get @base
    assert_select '.event-results__card', count: 0
    assert_select 'meta[name=robots][content*=noindex]'
    assert_empty EventDaySitemap.each_path.to_a
  end

  test 'populated discovery links and sitemap contain canonical URLs without filter queries' do
    get '/dates'
    assert_select '.event-results__discovery a[href="/dates/basketball"]'
    assert_select '.event-results__discovery a[href="/dates/prefectures/kanagawa"]'
    get '/dates/basketball'
    assert_select '.event-results__discovery a[href=?]', @base
    get event_prefecture_path('basketball', 'kanagawa')
    assert_select '.event-date-search a[href=?]', @base
    paths = EventDaySitemap.each_path.to_a
    [@base, @base + '/today', @base + '/2026/10/14', '/dates/basketball', '/dates/prefectures/kanagawa'].each { |path| assert_includes paths, path }
    refute paths.any? { |path| path.include?('?') }
    assert_equal paths.uniq, paths
  end

  test 'fixed URL conditions cannot be overwritten by query filters and forms can change conditions' do
    get @base, params: { event: 'missing', pref: 'missing' }
    assert_redirected_to @base
    follow_redirect!
    assert_select 'h1', text: '神奈川県のバスケイベント・練習会一覧'
    get '/dates', params: { pref: 'kanagawa' }
    assert_redirected_to '/dates/prefectures/kanagawa'
    get '/dates', params: { event: 'basketball', pref: 'kanagawa', date: '2026-10-14' }
    assert_redirected_to @base + '/2026/10/14'
    get @base + '/2026/010/014'
    assert_redirected_to @base + '/2026/10/14'
  end

  test 'public event schema contains Japan time and only published venue information' do
    get user_schedule_path(@circle, @schedule)
    assert_select 'link[rel=canonical][href=?]', "https://circle-book.com#{user_schedule_path(@circle, @schedule)}"
    event = css_select('script[type="application/ld+json"]').map { |node| JSON.parse(node.text) }.find { |data| data['@type'] == 'Event' }
    assert_equal '2026-10-14T18:00:00+09:00', event['startDate']
    assert_equal '2026-10-14T21:00:00+09:00', event['endDate']
    assert_equal '公開体育館', event.dig('location', 'name')
    assert_not_includes event.to_json, '非公開'
    assert_nil event['offers'], 'Do not invent a numeric price from free text'
    @schedule.update!(time_s: '23:00', time_e: '01:00', recruitment: '中止')
    get user_schedule_path(@circle, @schedule)
    event = css_select('script[type="application/ld+json"]').map { |node| JSON.parse(node.text) }.find { |data| data['@type'] == 'Event' }
    assert_equal '2026-10-15T01:00:00+09:00', event['endDate']
    assert_equal 'https://schema.org/EventCancelled', event['eventStatus']
    @schedule.update_column(:venue, nil)
    get user_schedule_path(@circle, @schedule)
    refute css_select('script[type="application/ld+json"]').any? { |node| JSON.parse(node.text)['@type'] == 'Event' }
  end

  test 'non sport genres use activity copy rather than practice or team recruitment' do
    @circle.event.update!(name: '読書', ruby: 'reading')
    get '/dates/reading/kanagawa'
    assert_response :success
    assert_select 'h1', text: '神奈川県の読書イベント・活動一覧'
    assert_select 'h1', text: /練習会|チーム募集/, count: 0
  end

  private

  def structured_graph
    css_select('script[type="application/ld+json"]').map { |node| JSON.parse(node.text) }.find { |data| data['@graph'] }['@graph']
  end
end
