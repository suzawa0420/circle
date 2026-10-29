require 'test_helper'
require_relative '../support/chat_records'

class ScheduleCalendarTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    travel_to Time.zone.local(2026, 10, 13, 12)
    create_chat_records
    @circle.update!(recruitment: '初心者歓迎')
    @open = event('2026-10-24', '夜のバスケ', capacity: 16)
    @few = event('2026-10-24', '昼のバスケ', capacity: 5)
    @full = event('2026-10-18', '満員のバスケ', capacity: 2)
    @cancelled = event('2026-10-21', '中止のバスケ', recruitment: '中止')
    @next = event('2026-11-07', '来月のバスケ')
    @past = 7.times.map { |i| event((Date.current - i - 1).iso8601, "過去のバスケ#{i}") }
    now = Time.current
    NameSchedule.insert_all!([@few, @full].flat_map do |schedule|
      [1, 1, 0, 2, nil].map { |answer| { schedule_id: schedule.id, answer: answer, created_at: now, updated_at: now } }
    end)
  end

  teardown { travel_back }

  test 'current month shows statuses and public details with bounded grouped counts' do
    instantiated = Hash.new(0)
    queries = []
    ActiveSupport::Notifications.subscribed(->(*args) { p = args.last; instantiated[p[:class_name]] += p[:record_count] }, 'instantiation.active_record') do
      ActiveSupport::Notifications.subscribed(->(*args) { p = args.last; queries << p[:sql] unless p[:cached] || p[:name] == 'SCHEMA' }, 'sql.active_record') do
        get user_schedules_path(@circle)
      end
    end
    assert_response :success
    assert_select '.schedule-calendar__month h2', text: '2026年 10月'
    assert_select '.schedule-calendar__day', count: 31
    assert_select '.schedule-calendar__day[aria-label*="10月24日（土） 2件"]', count: 1
    assert_select '#activity-list .schedule-calendar__event', count: 4
    %w[open few full cancelled].each { |key| assert_select "#activity-list .status-#{key}", count: 1 }
    assert_select '#past-activities .schedule-calendar__event', count: 0
    assert_select '.schedule-calendar__venue', text: /川崎市中原区/
    assert_not_includes response.body, '非公開体育館'
    assert_not_includes response.body, '非公開住所'
    assert_not_includes response.body, '非公開に近い長文'
    assert_equal 0, instantiated['NameSchedule']
    assert_equal 1, queries.count { |sql| sql.include?('GROUP BY "name_schedules"."schedule_id"') }
  end

  test 'day selection includes every activity on that day and never another circle' do
    other = User.create!(@circle.attributes.except('id', 'created_at', 'updated_at', 'unique_id').merge(name: '別のカレンダーサークル'))
    other.schedules.create!(day: '2026-10-24', title: '別サークルの予定', venue: '別会場')
    get user_schedules_path(@circle), params: { month: '2026-10', date: '2026-10-24' }
    assert_response :success
    assert_select '#activity-list-title', text: '10月24日（土）'
    assert_select '#activity-list .schedule-calendar__event', count: 2
    assert_select '.schedule-calendar__day.is-selected', count: 1
    assert_not_includes response.body, '別サークルの予定'
  end

  test 'month navigation crosses years and supports leap February and empty months' do
    get user_schedules_path(@circle), params: { month: '2026-12' }
    assert_response :success
    assert_select 'a[aria-label="次の月"][href*="month=2027-01"]'
    assert_select '.schedule-calendar__empty', text: 'この月の活動予定はありません。'
    get user_schedules_path(@circle), params: { month: '2028-02' }
    assert_select '.schedule-calendar__day', count: 29
    get user_schedules_path(@circle), params: { month: '2026-11' }
    assert_select '#activity-list .schedule-calendar__event', count: 1
    assert_select "#activity-list a[href='#{user_schedule_path(@circle, @next)}']"
  end

  test 'past list is opt in and paginated without hiding upcoming activities' do
    get user_schedules_path(@circle), params: { past: '1' }
    assert_response :success
    assert_select '#past-activities .schedule-calendar__event', count: 5
    assert_select '#past-activities a[href*="page=2"][href*="past=1"]'
    get user_schedules_path(@circle), params: { past: '1', page: 2 }
    assert_select '#past-activities .schedule-calendar__event', count: 2
    assert_select '#activity-list .schedule-calendar__event', count: 4
    get user_schedules_path(@circle), params: { month: '2026-10', date: @past.first.day }
    assert_select '#activity-list .status-ended', text: /開催終了/
  end

  test 'explicit cancellation and closed recruitment override capacity' do
    @open.update!(recruitment: '募集終了')
    @few.update!(recruitment: '中止')
    get user_schedules_path(@circle)
    assert_select '#activity-list .status-full', count: 2
    assert_select '#activity-list .status-cancelled', count: 2
    @open.update!(recruitment: '募集中', recruitment_numbers: 0)
    get user_schedules_path(@circle)
    assert_select '#activity-list .status-open', count: 1
    assert_select '.schedule-calendar__capacity', text: '募集人数：制限なし'
  end

  test 'invalid month and dates are rejected' do
    [{ month: '2026-13' }, { month: '2026-02', date: '2026-02-30' },
     { month: '2026-10', date: '2026-11-07' }, { month: ['2026-10'] }, { month: '0000-01' }].each do |params|
      assert_raises(ActiveRecord::RecordNotFound) { get user_schedules_path(@circle), params: params }
    end
  end

  test 'owner can still create and copy schedules' do
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    get user_schedules_path(@circle)
    assert_response :success
    assert_select "a[href='#{new_user_schedule_path(@circle)}']"
    assert_select '#schedule-calendar'
  end

  private

  def event(day, title, capacity: 16, recruitment: nil)
    @circle.schedules.create!(day: day, title: title, venue: '川崎市中原区',
      member_venue: '非公開体育館', venue_address: '非公開住所', note: '非公開に近い長文' * 100,
      recruitment_numbers: capacity, recruitment: recruitment, time_s: '18:50', time_e: '21:00')
  end
end
