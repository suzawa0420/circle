require 'test_helper'
require_relative '../support/chat_records'

class EventDayResultsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    travel_to Time.zone.local(2026, 10, 13, 12)
    create_chat_records
    @open = activity('夜のバスケ', time_s: '18:00', time_e: '21:00', recruitment_numbers: 10)
    @few = activity('残りわずかのバスケ', recruitment_numbers: 3)
    @full = activity('満員のバスケ', recruitment_numbers: 1)
    NameSchedule.insert_all!([{ schedule_id: @full.id, answer: 1, created_at: Time.current, updated_at: Time.current }])
    @cancelled = activity('中止のバスケ', recruitment: '中止')
    @ended = activity('終了したバスケ', time_s: '08:00', time_e: '10:00')
    @tomorrow = activity('明日のバスケ', day: '2026-10-14')
  end

  teardown { travel_back }

  test 'compact server rendered results show status and exclude private fields' do
    instantiated = Hash.new(0)
    ActiveSupport::Notifications.subscribed(->(*args) { p = args.last; instantiated[p[:class_name]] += p[:record_count] }, 'instantiation.active_record') do
      get '/dates/today'
    end
    assert_response :success
    assert_select '.event-results__card', count: 5
    %w[open few full cancelled ended].each { |status| assert_select ".event-results__status.status-#{status}", count: 1 }
    assert_select '.event-results__text h3', text: '夜のバスケ'
    assert_select '.event-results__time', text: '18:00–21:00'
    assert_not_includes response.body, '非公開会場'
    assert_not_includes response.body, '非公開住所'
    assert_not_includes response.body, '主催サークル'
    assert_equal 0, instantiated['NameSchedule']
    assert_select 'script[type="application/ld+json"]', minimum: 1
    first_two = css_select('.event-results__status').first(2).map(&:text)
    assert_equal ['募集中', '残りわずか'].sort, first_two.sort
  end

  test 'rotation is stable across pagination and changes daily with availability first' do
    30.times { |i| activity("追加イベント#{i}") }
    listing = EventDayListing.new(date: Date.current)
    ids = listing.schedules.map(&:id)
    assert_equal ids, listing.schedules.map(&:id)
    assert_equal ids.first(20), listing.schedules.page(1).per(20).map(&:id)
    assert_equal ids.drop(20), listing.schedules.page(2).per(20).map(&:id)
    other_seed = EventDayListing.new(date: Date.current, now: Time.current - 1.day).schedules.map(&:id)
    assert_not_equal ids, other_seed
    assert_equal [@full.id, @cancelled.id, @ended.id].sort, ids.last(3).sort
    get '/dates/today', params: { page: 2 }
    assert_response :success
    assert_select '.event-results__card', count: 15
    assert_select 'link[rel="canonical"][href="https://circle-book.com/dates/today?page=2"]'
  end

  test 'sorts and filters have canonical metadata with valid public links' do
    query = { event: @circle.event.ruby, pref: @circle.prefecture.kana }
    get '/dates/2026/10/13', params: query.merge(sort: '3', utm_source: 'test')
    assert_response :success
    assert_select 'link[rel="canonical"]', href: 'https://circle-book.com/dates/2026/10/13?' + query.to_query
    assert_select 'meta[name="robots"][content*="noindex"]'
    assert_select 'title', text: /東京都.*バスケ/
    get '/dates/today', params: query.merge(sort: '1')
    assert_response :success
    assert_select 'meta[name="robots"][content*="noindex"]', count: 0
    assert_select 'h1', text: /今日・東京都のバスケ/
    assert_select 'a[href*="/dates/tomorrow?event="]'
    get '/dates/today', params: { sort: '2' }
    assert_response :success
    assert_select 'meta[name="robots"][content*="noindex"]'
  end

  test 'today and tomorrow roll over in Japan and empty pages are not indexed' do
    get '/dates/tomorrow'
    assert_select '.event-results__text h3', text: '明日のバスケ'
    travel_to Time.zone.local(2026, 10, 14, 0, 1)
    get '/dates/today'
    assert_select '.event-results__text h3', text: '明日のバスケ'
    get '/dates/tomorrow'
    assert_response :success
    assert_select 'meta[name="robots"][content*="noindex"]'
    assert_raises(ActiveRecord::RecordNotFound) { get '/dates/today', params: { page: 9 } }
    assert_raises(ActiveRecord::RecordNotFound) { get '/dates/2026/2/30' }
    assert_raises(ActiveRecord::RecordNotFound) { get '/dates/today', params: { pref: 'does-not-exist' } }
  end

  test 'Japanese clock order and overnight activity are handled correctly' do
    morning = activity('明日の朝', day: '2026-10-14', time_s: '07:00', time_e: '09:00')
    evening = activity('明日の夜', day: '2026-10-14', time_s: '19:00', time_e: '21:00')
    overnight = activity('深夜の活動', time_s: '23:00', time_e: '01:00')
    listing = EventDayListing.new(date: Date.current, sort: '3')
    assert_equal ['open', '募集中'], listing.status(listing.schedules.find(overnight.id))
    assert_equal ['open', '募集中'], listing.status(listing.schedules.find(@open.id))
    assert_equal ['ended', '開催終了'], listing.status(listing.schedules.find(@ended.id))
    ids = EventDayListing.new(date: Date.current + 1, sort: '3').schedules.map(&:id)
    assert_operator ids.index(morning.id), :<, ids.index(evening.id)
  end

  test 'sitemap lists populated canonical dates and filtered relative pages only' do
    activity('過去のバスケ', day: '2026-10-12')
    paths = EventDaySitemap.each_path.to_a
    assert_includes paths, '/dates/2026/10/13'
    assert_includes paths, '/dates/today'
    assert_includes paths, '/dates/tomorrow'
    assert_includes paths, '/dates/today?' + { event: @circle.event.ruby, pref: @circle.prefecture.kana }.to_query
    assert_not_includes paths, '/dates/2026/10/12'
    assert_not_includes paths, '/dates/2026/10/15'
    assert_equal paths.uniq, paths
    @circle.update_columns(publication_status: 'draft')
    assert_empty EventDaySitemap.each_path.to_a
    get '/dates/today'
    assert_select '.event-results__card', count: 0
  end

  private

  def activity(title, **attrs)
    @circle.schedules.create!({ title: title, day: '2026-10-13', venue: '公開体育館',
      member_venue: '非公開会場', venue_address: '非公開住所' }.merge(attrs))
  end
end
