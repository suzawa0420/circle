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
      bases = [EventDayListing.path(date)]
      bases << '/dates/today' if date == today
      bases << '/dates/tomorrow' if date == today + 1
      event = events[event_id].presence
      pref = prefectures[prefecture_id].presence
      filters = [{}]
      filters << { event: event } if event && event != 'nil'
      filters << { pref: pref } if pref && pref != 'nil'
      filters << { event: event, pref: pref } if event && pref && event != 'nil' && pref != 'nil'
      bases.product(filters).each do |base, query|
        path = base + (query.empty? ? '' : '?' + query.to_query)
        yield path if seen.add?(path)
      end
    end
  end
end
