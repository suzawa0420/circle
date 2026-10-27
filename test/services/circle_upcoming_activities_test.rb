require 'test_helper'

class CircleUpcomingActivitiesTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  def activity(id, day, start_at: nil, end_at: nil, recruitment: '募集中')
    Schedule.new(id: id, day: day, time_s: start_at, time_e: end_at, recruitment: recruitment)
  end

  test 'uses Japan date and clock including morning and overnight activities' do
    now = Time.utc(2026, 10, 26, 15, 30) # October 27, 00:30 JST
    schedules = [activity(1, '2026-10-26'), activity(2, '2026-10-27', start_at: '00:00', end_at: '00:15'),
      activity(3, '2026-10-27', start_at: '09:00'), activity(4, '2026-10-27', start_at: '23:00', end_at: '01:00'),
      activity(5, '2026-10-28', start_at: '08:00'), activity(6, '2026-10-28', recruitment: '中止')]
    assert_equal [3, 4, 5], CircleUpcomingActivities.from(schedules, now: now).map(&:id)
    assert_equal [4, 5], CircleUpcomingActivities.from(schedules, now: Time.utc(2026, 10, 27, 14, 30)).map(&:id)
  end

  test 'empty past cancelled invalid dates and missing times do not invent a date' do
    now = Time.zone.local(2026, 10, 27, 12)
    assert_empty CircleUpcomingActivities.from([], now: now)
    assert_empty CircleUpcomingActivities.from([activity(1, '2026-10-26'), activity(2, 'bad'),
      activity(3, nil), activity(4, '2026-10-28', recruitment: '中止')], now: now)
    assert_equal [5], CircleUpcomingActivities.from([activity(5, '2026-10-27')], now: now).map(&:id)
    assert_empty CircleUpcomingActivities.from([activity(6, '2026-10-27', start_at: '12:00')], now: now)
  end

  test 'sorts same-day activities by Japanese start time and caps shared list at seven' do
    schedules = (1..10).map { |i| activity(i, '2026-10-28', start_at: "#{i + 7}:00") }.reverse
    assert_equal (1..7).to_a, CircleUpcomingActivities.from(schedules, now: Time.zone.local(2026, 10, 27)).map(&:id)
  end
end
