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

  test 'flagged organizers follow ordinary circles for every public sort before pagination' do
    normal = @circle
    flagged = [1, 2, 3].map do |check|
      owner = AdminUser.create!(email: "flagged-#{check}@example.test", password: 'test-password-123', check: check)
      circle = normal.dup
      circle.assign_attributes(admin_user: owner, name: "注意対象サークル#{check}", cb_point: 100,
                               last_post: '2099-12-31', created_at: 1.day.from_now)
      circle.save!
      circle.schedules.create!(title: "注意対象イベント#{check}", day: '2026-10-13', venue: '体育館',
                               time_s: '01:00', created_at: 1.day.from_now)
      circle
    end
    normal.update_columns(cb_point: 0, last_post: '2020-01-01', switch: '募集終了')
    scopes = %i[sort_1 sort_2 sort_3 user_sort_1 user_sort_2 user_sort_3 user_order]
    scopes.each do |sort|
      relation = User.where(id: [normal.id, *flagged.map(&:id)]).pref.public_send(sort)
      assert_equal normal.id, relation.limit(1).first.id, sort.to_s
      assert_equal normal.id, relation.page(1).per(1).first.id, sort.to_s
    end
    [nil, '1', '2', '3'].each do |sort|
      listing = EventDayListing.new(date: Date.current, sort: sort)
      schedules = listing.schedules.to_a
      assert_equal [normal.id], schedules.first(5).map(&:user_id).uniq
      assert_equal flagged.first(2).map(&:id).sort, schedules.drop(5).map(&:user_id).sort
      assert_not_includes schedules.map(&:user_id), flagged.last.id
      upcoming = EventDayListing.new(date: Date.current, sort: sort, upcoming: true)
      assert_equal normal.id, upcoming.schedules.page(1).per(1).first.user_id
    end
    get '/dates'
    assert_response :success
    assert_select '.event-results__card .event-results__text h3' do |titles|
      assert_equal ['注意対象イベント1', '注意対象イベント2'].sort, titles.to_a.last(2).map(&:text).sort
    end
    [Blog, Match, Link].each do |model|
      result = model.insert_all!([normal, flagged.first].map do |circle|
        { user_id: circle.id, created_at: Time.current, updated_at: circle == normal ? 1.day.ago : Time.current }
      end)
      assert_equal normal.id, model.where(id: result.rows.flatten).order(updated_at: :desc).moderation_last.limit(1).first.user_id
    end
    flagged.first.admin_user.update!(check: nil)
    assert_equal flagged.first.id, User.where(id: [normal.id, flagged.first.id]).sort_2.first.id
  end

  test 'circle search has twelve consecutive date links without duplicate period or date forms' do
    travel_to Time.zone.local(2026, 12, 29, 12)
    get event_prefecture_path(@circle.event.ruby, @circle.prefecture.kana)
    assert_response :success
    assert_select '.event-date-search' do
      assert_select 'h2', text: '日付からイベントを探す'
      assert_select '.event-results__shortcuts, form, input[type=date]', count: 0
      assert_select '.event-results__days a', count: 12 do |links|
        links.each_with_index do |link, index|
          uri = URI.parse(link['href'])
          assert_equal EventSearchPage.path(event: @circle.event.ruby, prefecture: @circle.prefecture.kana, date: Date.current + index), uri.path
          assert_nil uri.query
        end
      end
    end
  end

  test 'all dates hub uses common cards and chronological days without loading attendance records' do
    activity('過去の活動', day: '2026-10-12')
    morning = activity('明日の朝の活動', day: '2026-10-14', time_s: '07:00', time_e: '09:00')
    records = Hash.new(0)
    ActiveSupport::Notifications.subscribed(->(*args) { p = args.last; records[p[:class_name]] += p[:record_count] }, 'instantiation.active_record') do
      get '/dates'
    end
    assert_response :success
    assert_select '.event-results--hub', count: 1
    assert_select '.event-results__card', count: 7
    assert_select '.event-results__date-group', count: 2
    assert_select '.event-results__days a', count: 5
    assert_select '.event-results__shortcuts a[href="/dates/today"]'
    assert_select '.event-results__shortcuts a[href="/dates/tomorrow"]'
    assert_select '.schedule_item_wrap, .e_header_wrap', count: 0
    assert_select ".event-results__card[href='#{user_schedule_path(@circle, morning)}'] .status-open", text: '募集中'
    assert_equal 0, records['NameSchedule']
    assert_not response.body.include?('過去の活動'), 'Past activities must not appear in the upcoming hub'
    assert_select 'link[rel="canonical"][href="https://circle-book.com/dates"]'
    assert_select 'meta[name="robots"][content*="noindex"]', count: 0
  end

  test 'hub filters preserve canonical URLs and date input opens the corresponding day' do
    query = { event: @circle.event.ruby, pref: @circle.prefecture.kana }
    get '/dates', params: query.merge(utm_source: 'test')
    assert_response :moved_permanently
    follow_redirect!
    assert_response :success
    assert_select 'link[rel="canonical"]', href: 'https://circle-book.com' + filtered_path
    assert_select 'h1', text: /東京都のバスケ/
    assert_select 'form[method="get"][action="/dates"] input[type="date"][name="date"]'
    get '/dates', params: query.merge(date: '2026-10-14')
    assert_redirected_to filtered_path(date: Date.new(2026, 10, 14))
    follow_redirect!
    assert_select '.event-results__text h3', text: '明日のバスケ'
    assert_raises(ActiveRecord::RecordNotFound) { get '/dates', params: { date: '2026-02-30' } }
    assert_raises(ActiveRecord::RecordNotFound) { get '/dates', params: { page: '-1' } }
    assert_raises(ActiveRecord::RecordNotFound) { get '/dates', params: { event: 'not-found' } }
  end

  test 'hub pagination and hidden circles preserve complete bounded result pages' do
    30.times { |i| activity("来週の活動#{i}", day: '2026-10-20') }
    get '/dates', params: { page: 2 }
    assert_response :success
    assert_select '.event-results__card', count: 16
    assert_select 'link[rel="canonical"][href="https://circle-book.com/dates?page=2"]'
    @circle.update_columns(publication_status: 'draft')
    get '/dates'
    assert_response :success
    assert_select '.event-results__card', count: 0
    assert_select 'meta[name="robots"][content*="noindex"]'
    assert_raises(ActiveRecord::RecordNotFound) { get '/dates', params: { page: 2 } }
  end

  test 'missing photos use existing sport images and category fallback across result pages' do
    @circle.update!(recruitment: '初心者歓迎')
    @circle.event.update!(ruby: 'basketball', txt: 'バスケサークル')
    get '/dates/today'
    assert_select '.event-results__image[src="/images/events/basketball.jpg"]', count: 5
    assert_not_includes response.body, '/images/default.png'
    get '/dates'
    assert_select '.event-results__image[src="/images/events/basketball.jpg"]', minimum: 1
    get user_schedule_path(@circle, @open)
    assert_select '.schedule_top_image > img.top_img[src="/images/events/basketball.jpg"]', count: 1

    @circle.event.update!(ruby: 'unknown-sport')
    @circle.event.category.update!(kana: 'ball-sports')
    get '/dates/today'
    assert_select '.event-results__image[src="/images/categories/ball-sports.jpg"]', count: 5
    @circle.event.category.update!(kana: '../../missing')
    get '/dates/today'
    assert_select '.event-results__image[src="/images/events/event.jpg"]', count: 5
  end

  test 'uploaded schedule images retain their cache version with the narrow projection' do
    @open.update_column(:top_image, 'event-photo.jpg')
    schedule = EventDayListing.new(date: Date.current).schedules.find(@open.id)
    file = Struct.new(:location) do
      def url(*) = location
      def empty? = false
    end.new('/uploads/event-photo.jpg')
    schedule.top_image.instance_variable_set(:@file, file)
    assert_equal "/uploads/event-photo.jpg?v=#{@open.updated_at.utc.to_i}", schedule.top_image.url
    assert_equal schedule.top_image.url, SchedulesController.helpers.schedule_image_source(schedule)
  end

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
    assert_response :moved_permanently
    follow_redirect!
    assert_response :success
    assert_select 'link[rel="canonical"]', href: 'https://circle-book.com' + filtered_path(date: Date.current)
    assert_select 'meta[name="robots"][content*="noindex"]'
    assert_select 'title', text: /東京都.*バスケ/
    get '/dates/today', params: query.merge(sort: '1')
    assert_response :moved_permanently
    follow_redirect!
    assert_response :success
    assert_select 'meta[name="robots"][content*="noindex"]', count: 0
    assert_select 'h1', text: /今日開催予定の東京都のバスケ/
    assert_select 'a[href=?]', filtered_path(period: 'tomorrow')
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

  test 'weekly results include exactly Monday through Sunday and preserve SEO filters' do
    monday = activity('月曜の活動', day: '2026-10-12')
    sunday = activity('日曜の活動', day: '2026-10-18')
    following = activity('翌週の活動', day: '2026-10-19')
    activity('翌々週の活動', day: '2026-10-26')
    query = { event: @circle.event.ruby, pref: @circle.prefecture.kana }
    get '/dates/this_week', params: query.merge(utm_source: 'test')
    assert_response :moved_permanently
    follow_redirect!
    assert_response :success
    assert_select 'h1', text: /今週開催予定の東京都のバスケ/
    assert_select '.event-results__header p', text: /2026年10月12日（月）〜2026年10月18日（日）/
    assert_select '.event-results__days a', count: 7
    assert_select '.event-results__card', count: 8
    assert_select ".event-results__card[href='#{user_schedule_path(@circle, monday)}']", count: 1
    assert_select ".event-results__card[href='#{user_schedule_path(@circle, sunday)}'] .event-results__time", text: /10月18日.*日/m
    assert_select ".event-results__card[href='#{user_schedule_path(@circle, following)}']", count: 0
    assert_select 'link[rel="canonical"]', href: 'https://circle-book.com' + filtered_path(period: 'this_week')
    assert_select 'meta[name="description"]', content: /今週.*10月12日.*10月18日.*バスケ/
    assert_select 'meta[name="robots"][content*="noindex"]', count: 0
    assert_select 'a[href=?]', filtered_path(period: 'next_week')
    assert_select 'script[type="application/ld+json"]', text: /ItemList/
    get '/dates/next_week', params: query
    assert_response :moved_permanently
    follow_redirect!
    assert_response :success
    assert_select '.event-results__card', count: 1
    assert_select 'h1', text: /来週開催予定の東京都のバスケ/
    assert_select 'link[rel="canonical"]', href: 'https://circle-book.com' + filtered_path(period: 'next_week')
    get '/dates/next_week', params: { sort: '3' }
    assert_select 'meta[name="robots"][content*="noindex"]'
    assert_raises(ActiveRecord::RecordNotFound) { get '/dates/next_week', params: { page: 9 } }
    assert_raises(ActiveRecord::RecordNotFound) { get '/dates/this_week', params: { sort: 'invalid' } }
  end

  test 'week boundaries roll over at Japan Monday and empty or hidden weeks are not indexed' do
    activity('日曜の夜', day: '2026-10-18')
    activity('月曜の朝', day: '2026-10-19')
    travel_to Time.utc(2026, 10, 18, 14, 59)
    get '/dates/this_week'
    assert_select '.event-results__header p', text: /10月12日（月）〜2026年10月18日（日）/
    travel_to Time.utc(2026, 10, 18, 15, 0)
    get '/dates/this_week'
    assert_select '.event-results__header p', text: /10月19日（月）〜2026年10月25日（日）/
    assert_select '.event-results__card', count: 1
    get '/dates/next_week'
    assert_select 'meta[name="robots"][content*="noindex"]'
    @circle.update_columns(publication_status: 'draft')
    get '/dates/this_week'
    assert_select '.event-results__card', count: 0
    assert_select 'meta[name="robots"][content*="noindex"]'
    assert_empty EventDaySitemap.each_path.to_a
  end

  test 'sitemap lists populated canonical dates and filtered relative pages only' do
    activity('過去のバスケ', day: '2026-10-12')
    paths = EventDaySitemap.each_path.to_a
    assert_includes paths, '/dates/2026/10/13'
    assert_includes paths, '/dates/today'
    assert_includes paths, '/dates/tomorrow'
    assert_includes paths, '/dates/this_week'
    assert_not_includes paths, '/dates/next_week'
    activity('来週の日曜', day: '2026-10-25')
    paths = EventDaySitemap.each_path.to_a
    assert_includes paths, '/dates/next_week'
    assert_includes paths, filtered_path(period: 'next_week')
    assert_includes paths, filtered_path(period: 'today')
    assert_not_includes paths, '/dates/2026/10/12'
    assert_not_includes paths, '/dates/2026/10/15'
    assert_equal paths.uniq, paths
    @circle.update_columns(publication_status: 'draft')
    assert_empty EventDaySitemap.each_path.to_a
    get '/dates/today'
    assert_select '.event-results__card', count: 0
  end

  private

  def filtered_path(**options)
    EventSearchPage.path(event: @circle.event.ruby, prefecture: @circle.prefecture.kana, **options)
  end

  def activity(title, **attrs)
    @circle.schedules.create!({ title: title, day: '2026-10-13', venue: '公開体育館',
      member_venue: '非公開会場', venue_address: '非公開住所' }.merge(attrs))
  end
end
