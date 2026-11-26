require 'test_helper'
require_relative '../support/chat_records'

class HomePortalTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    travel_to Time.zone.local(2026, 10, 14, 12)
    create_chat_records
  end
  teardown { travel_back }

  test 'homepage has two vertical preview sections and all five directory links' do
    @circle.update!(recruitment: '初心者歓迎、一緒に活動しましょう')
    7.times do |index|
      @circle.schedules.create!(day: Date.current.iso8601, title: "今日のバスケ#{index}", venue: '公開体育館', time_s: '18:00', time_e: '20:00', recruitment: '募集中', cost: '500円', recruitment_numbers: 10)
    end
    get root_path
    assert_response :success
    assert_select '.home-portal__layout .home-portal__main .home-portal__section', count: 2
    assert_select '.home-portal__sidebar nav[aria-label="目的から探す"] .home-service', count: 5
    %w[circles dates blogs matches places].each { |path| assert_select ".home-service[href='/#{path}']", count: 1 }
    assert_select '.home-service__arrow', count: 5
    assert_select '.home-service--places[href="/places"] > span', text: 'コート・体育館を探す', count: 1
    assert_select '#home-circles .home-portal__list > li .cb-circle-list-card', count: 1
    assert_select '#home-circles .cb-circle-list-card__link[href=?]', circle_path(@circle)
    assert_select '#home-events .home-portal__list > li .event-list-card', count: 1
    assert_select '#home-events .event-results__status.status-open', count: 1
    assert_select '#home-events .event-results__card', text: /参加費：500円/, count: 1
    expected_events = EventDayListing.new(date: Date.current, sort: '3').schedules.limit(1).map { |s| user_schedule_path(@circle, s) }
    assert_equal expected_events, css_select('#home-events .event-list-card').map { |a| a['href'] }
    assert_select '#home-blogs, #home-matches, #home-places, .home-portal__rail, .home-portal__slide-hint', count: 0
    ['/circles', '/dates'].each { |path| assert_select ".home-portal__more[href='#{path}']", count: 1 }
    assert_select '.home-portal .pagination, .home-portal .list_ad', count: 0

    @circle.update_columns(publication_status: 'draft')
    get root_path
    assert_response :success
    assert_select '#home-circles .home-portal__item, #home-events .home-portal__item', count: 0
    assert_select '#home-events .home-portal__empty', text: /今日のイベントはまだありません/
  end

  test 'homepage picks earliest eligible events from distinct sports and prefers different organizers' do
    climbing = Event.create!(name: '登山', ruby: 'preview-climbing', category: @circle.category, order: '2')
    tennis = Event.create!(name: 'テニス', ruby: 'preview-tennis', category: @circle.category, order: '3')
    dance = Event.create!(name: 'バレエ', ruby: 'preview-ballet', category: @circle.category, order: '4')
    new_owner = AdminUser.create!(email: 'preview-other@example.test', password: 'test-password-123', email_verified_at: Time.current)
    make_circle = ->(name, owner, event) do
      User.create!(name: name, appeal: @circle.appeal, category: @circle.category,
                   event: event, prefecture: @circle.prefecture, admin_user: owner, switch: '募集中')
    end
    extra_climbing = make_circle.call('同種目の登山会', new_owner, climbing)
    same_owner_tennis = make_circle.call('近所のテニス会', new_owner, tennis)
    other_tennis = make_circle.call('もう一つのテニス会', @owner, tennis)
    draft = make_circle.call('非公開の体験会', @owner, dance)
    draft.update_columns(publication_status: 'draft')
    today = Date.current.iso8601
    make_schedule = ->(circle, title, time, day = today) do
      circle.schedules.create!(day: day, title: title, venue: '公開体育館', time_s: time, time_e: '23:00', recruitment: '募集中')
    end

    first = make_schedule.call(extra_climbing, '最初の登山', '13:00')
    12.times { |index| make_schedule.call(extra_climbing, "同種目の活動#{index}", '13:15') }
    preferred = make_schedule.call(other_tennis, '別主催者のテニス', '17:00')
    declined = make_schedule.call(same_owner_tennis, '同じ主催者のテニス', '14:00')
    make_schedule.call(draft, '非公開の今日', '12:30')
    make_schedule.call(other_tennis, '別日の開催', '12:30', Date.tomorrow.iso8601)
    third = make_schedule.call(@circle, '今日のバスケ', '18:00')

    get root_path
    assert_response :success
    assert_equal [first, preferred, third].map { |schedule| user_schedule_path(schedule.user_id, schedule) },
                 css_select('#home-events .event-list-card').map { |a| a['href'] }
    assert_equal %w[登山 テニス バスケ], css_select('#home-events .event-list-card__meta .event-list-card__fact').map(&:text)

    get dates_path
    assert_response :success
    assert_select 'a.event-list-card[href=?]', user_schedule_path(same_owner_tennis, declined)
  end

  test 'circle location retains its full text despite its single-line card layout' do
    area = '長い活動場所' * 14
    @circle.update_columns(area: area, user_time: '2026-10-14')
    get root_path
    assert_response :success
    full_location = "東京都・#{area}"
    assert_select '#home-circles .cb-circle-list-card__fact--location > span[title=?]', full_location, text: full_location
    assert_select '#home-circles .cb-circle-list-card__updated[datetime="2026-10-14"]', text: '2026年10月14日'
  end

  test 'homepage skips the queries for removed previews and does not perform separate existence scans' do
    queries = []
    subscriber = ->(*args) { queries << args.last }
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') { get root_path }
    assert_response :success
    %w[User Schedule Blog Match Place].each do |model|
      refute_includes queries.map { |q| q[:name] }, "#{model} Exists?"
    end
    assert_empty queries.grep_v(nil).select { |q| q[:sql].to_s.match?(/FROM "(?:blogs|matches|places)"/i) }
  end

  test 'circle previews match the popular list ordering and stop at three' do
    @circle.update_columns(last_post: Time.current)
    6.times do |index|
      User.create!(name: "週末サークル#{index}", appeal: @circle.appeal, category: @circle.category,
                   event: @circle.event, prefecture: @circle.prefecture, admin_user: @owner,
                   switch: '募集中', cb_point: index * 10, last_post: Time.current - (index + 1).hours)
    end
    expected = User.publicly_visible.sort_2.limit(3).map { |circle| circle_path(circle) }
    get root_path
    assert_response :success
    assert_equal expected, css_select('#home-circles .cb-circle-list-card__link').map { |link| link['href'] }
  end

  test 'homepage uses the approved headline and synchronized search and social metadata' do
    get root_path
    assert_response :success
    headline = '近くで見つける スポーツと趣味のサークル'
    assert_select 'h1', count: 1 do
      assert_select 'br', count: 1
    end
    assert_equal headline.delete(' '), css_select('h1').sole.text.gsub(/[[:space:]]+/, '')
    assert_select '.home-portal__hero-description-line', count: 3
    assert_select '.home-portal__hero-search[href="/circles"] svg.cb-icon--search', count: 1
    assert_select 'title', text: /#{headline}/
    assert_select 'meta[property="og:title"][content=?]', headline
    assert_select 'meta[name="twitter:title"][content=?]', headline
    desc = css_select('meta[name=description]').sole['content']
    assert_includes desc, '新しい趣味を始めたいときも'
    assert_select 'meta[property="og:description"][content=?]', desc
    assert_select 'meta[name="twitter:description"][content=?]', desc
    assert_select 'meta[property="og:image"]', count: 1
    assert_select 'meta[name=robots][content*="noindex"]', count: 0
  end
end
