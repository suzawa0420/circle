# Share the detail page's existing schedule load; never read participant-only
# venue/address fields or attendance records for this public summary.
class CircleUpcomingActivities
  def self.from(schedules, now: Time.current)
    now = now.in_time_zone('Tokyo')
    schedules.filter_map do |schedule|
      next if schedule.recruitment == '中止'
      day = Date.iso8601(schedule.day)
      next if day < now.to_date
      start_time = clock_on(day, schedule.time_s)
      end_time = clock_on(day, schedule.time_e)
      end_time += 1.day if end_time && start_time && end_time < start_time
      next if day == now.to_date && (end_time || start_time)&.<=(now)
      [schedule, start_time || day.in_time_zone('Tokyo')]
    rescue Date::Error, TypeError
      # Legacy malformed dates cannot become an invented activity date.
      next
    end.sort_by { |schedule, time| [time, schedule.id] }.map(&:first).first(7)
  end

  def self.clock_on(day, value)
    return unless value
    clock = value.in_time_zone('Tokyo')
    Time.find_zone!('Tokyo').local(day.year, day.month, day.day, clock.hour, clock.min, clock.sec)
  end
  private_class_method :clock_on
end
