# Run with: bundle exec rails test test/performance/schedule_day_queries_check.rb
# Uses the normal isolated Rails test database, never a production connection.
require_relative '../test_helper'
require_relative '../support/chat_records'

class ScheduleDayQueriesTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  include ChatRecords

  test 'day filtering and attendance aggregation only instantiate a single results page' do
    create_chat_records
    45.times do |i|
      @circle.schedules.create!(day: '2026-10-17', title: "検証イベント#{i}", venue: '公開体育館')
    end
    listing = EventDayListing.new(date: Date.new(2026, 10, 17), event: @circle.event, prefecture: @circle.prefecture)
    records = Hash.new(0)
    schedules = nil
    ActiveSupport::Notifications.subscribed(->(*args) { p = args.last; records[p[:class_name]] += p[:record_count] }, 'instantiation.active_record') do
      schedules = listing.schedules.page(2).per(20).to_a
      assert_equal 45, listing.total_count
    end
    assert_equal 20, schedules.size
    assert_equal 20, records['Schedule']
    assert_equal 1, records['User']
    assert_equal 0, records['NameSchedule']
    assert_not schedules.first.has_attribute?(:note)
    assert_not schedules.first.has_attribute?(:member_venue)
    assert_not schedules.first.has_attribute?(:venue_address)
  end
end
