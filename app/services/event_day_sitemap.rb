class EventDaySitemap
  # Only real, public event populations produce URLs. SitemapGenerator handles
  # splitting the result into files within Google's per-file limits.
  def self.each_path(today: Time.current.in_time_zone('Tokyo').to_date)
    return enum_for(__method__, today: today) unless block_given?

    events = Event.pluck(:id, :ruby).to_h
    prefectures = Prefecture.pluck(:id, :kana).to_h
    seen = Set.new
    populations = EventDayListing.public_schedules.joins(:user)
      .where(day: today.iso8601..'2100-12-31')
      .group('schedules.day', 'users.event_id', 'users.prefecture_id')
      .pluck('schedules.day', 'users.event_id', 'users.prefecture_id')
    populations.each do |day, event_id, prefecture_id|
      begin
        date = Date.iso8601(day)
      rescue Date::Error
        next
      end
      next unless date.iso8601 == day
      periods = []
      periods << 'today' if date == today
      periods << 'tomorrow' if date == today + 1
      week_start = today.beginning_of_week(:monday)
      periods << 'this_week' if (week_start..week_start + 6).cover?(date)
      periods << 'next_week' if (week_start + 7..week_start + 13).cover?(date)
      event = events[event_id].presence
      pref = prefectures[prefecture_id].presence
      filters = [{}]
      filters << { event: event } if event && event != 'nil'
      filters << { prefecture: pref } if pref && pref != 'nil'
      filters << { event: event, prefecture: pref } if event && pref && event != 'nil' && pref != 'nil'
      filters.each do |filter|
        paths = [EventSearchPage.path(**filter), EventSearchPage.path(**filter, date: date)]
        paths.concat(periods.map { |period| EventSearchPage.path(**filter, period: period) })
        paths.each { |path| yield path if seen.add?(path) }
      end
    end
  end
end
