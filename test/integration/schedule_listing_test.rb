require 'test_helper'
require_relative '../support/chat_records'

class ScheduleListingTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    @circle.update!(recruitment: '初心者歓迎')
    @current = schedule_on(Date.current, '閲覧中の予定')
    @future = 12.times.map { |i| schedule_on(Date.current + i + 1, "今後の予定#{i}") }
    @past = 8.times.map { |i| schedule_on(Date.current - i - 1, "過去の予定#{i}") }
    now = Time.current
    NameSchedule.insert_all!((@future + @past).flat_map do |schedule|
      [1, 1, 0, 2, nil].map do |answer|
        { schedule_id: schedule.id, answer: answer, comment: '表示には不要な回答本文', created_at: now, updated_at: now }
      end
    end)
  end

  test 'public detail keeps every related upcoming date and aggregates accepted answers without loading them' do
    records = Hash.new(0)
    queries = []
    listener = ->(*args) { payload = args.last; records[payload[:class_name]] += payload[:record_count] }
    sql_listener = ->(*args) { payload = args.last; queries << payload[:sql] unless payload[:cached] || payload[:name] == 'SCHEMA' }
    ActiveSupport::Notifications.subscribed(listener, 'instantiation.active_record') do
      ActiveSupport::Notifications.subscribed(sql_listener, 'sql.active_record') do
        get user_schedule_path(@circle, @current)
      end
    end
    assert_response :success
    @future.each { |schedule| assert_select ".schedule_list_wrap a[href='#{user_schedule_path(@circle, schedule)}']", count: 1 }
    @past.first(5).each { |schedule| assert_select ".schedule_list_wrap a[href='#{user_schedule_path(@circle, schedule)}']", count: 1 }
    @past.drop(5).each { |schedule| assert_select ".schedule_list_wrap a[href='#{user_schedule_path(@circle, schedule)}']", count: 0 }
    assert_select ".schedule_list_wrap a[href='#{user_schedule_path(@circle, @current)}']", count: 0
    assert_select '.schedule_list .schedule_member', text: /参加人数：2/, count: 17
    assert_equal 0, records['NameSchedule'], 'Participant rows and comments must not be loaded for counts'
    assert_equal 1, queries.count { |sql| sql.include?('GROUP BY "name_schedules"."schedule_id"') }
  end

  test 'page two preserves past pagination and omits upcoming records' do
    get user_schedule_path(@circle, @current), params: { page: 2 }
    assert_response :success
    @future.each { |schedule| assert_select ".schedule_list_wrap a[href='#{user_schedule_path(@circle, schedule)}']", count: 0 }
    @past.drop(5).each { |schedule| assert_select ".schedule_list_wrap a[href='#{user_schedule_path(@circle, schedule)}']", count: 1 }
    assert_select '.schedule_list .schedule_member', text: /参加人数：2/, count: 3
  end

  test 'excluding the viewed past schedule does not move the pagination boundary' do
    listing = ScheduleListingData.new(upcoming: @circle.schedules.where('day > ?', Date.yesterday),
      past: @circle.schedules.where('day <= ?', Date.yesterday).order(day: :desc).page(1),
      excluded_id: @past.first.id, show_upcoming: false)
    assert_empty listing.upcoming
    assert_equal @past[1, 4].map(&:id), listing.past.map(&:id)
    assert_equal 8, listing.past_page.total_count
    assert_equal 2, listing.past_page.total_pages
    assert listing.past.none? { |schedule| schedule.has_attribute?(:note) || schedule.has_attribute?(:member_venue) }
    assert_equal [2], listing.past.map { |schedule| listing.accepted_count(schedule) }.uniq
  end

  private

  def schedule_on(day, title)
    @circle.schedules.create!(day: day.iso8601, title: title, venue: 'テスト会場',
      note: '一覧で不要な長い本文' * 1000, recruitment_numbers: 5)
  end
end
