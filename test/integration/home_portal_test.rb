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
    assert_select '#home-circles .home-portal__list > li .cb-circle-list-card', count: 1
    assert_select '#home-circles .cb-circle-list-card__link[href=?]', circle_path(@circle)
    assert_select '#home-events .home-portal__list > li .event-list-card', count: 3
    assert_select '#home-events .event-results__status.status-open', count: 3
    assert_select '#home-events .event-results__card', text: /参加費：500円/, count: 3
    expected_events = EventDayListing.new(date: Date.current).schedules.limit(3).map { |s| user_schedule_path(@circle, s) }
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
