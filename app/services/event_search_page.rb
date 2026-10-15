# Canonical URLs and copy for public event listings. Event pages describe
# individual opportunities to participate, independently of circle recruitment.
class EventSearchPage
  PERIODS = %w[today tomorrow this_week next_week].freeze
  PRACTICE_EVENTS = %w[basketball badminton volleyball futsal soccer tennis table-tennis baseball softball handball dodgeball].freeze

  def self.path(event: nil, prefecture: nil, period: nil, date: nil)
    parts = ['/dates']
    if event.present?
      parts << event
      parts << prefecture if prefecture.present?
    elsif prefecture.present?
      parts.concat(['prefectures', prefecture])
    end
    parts << period if PERIODS.include?(period)
    parts.concat([date.year, date.month, date.day]) if date
    parts.join('/')
  end

  def self.subject(event)
    return 'イベント・体験会' unless event
    practice = PRACTICE_EVENTS.include?(event.ruby) || event.name.to_s.match?(/バスケ|バドミントン|バレー|フットサル|サッカー|テニス|卓球|野球|ソフトボール|ハンドボール|ドッジボール/)
    "#{event.name}イベント・#{practice ? '練習会' : '活動'}"
  end

  def self.title(event:, prefecture:, period_label: nil, page: nil)
    title = "#{period_label.present? ? period_label + '・' : ''}#{prefecture&.name || '全国'}の#{subject(event)}一覧"
    title += "（#{page.to_i}ページ目）" if page.to_i > 1
    title
  end

  # Discover only combinations with actual upcoming public schedules. Grouped
  # IDs avoid loading circle profiles or individual schedule bodies.
  def self.populations(today: Time.current.in_time_zone('Tokyo').to_date, event: nil, prefecture: nil)
    relation = EventDayListing.public_schedules.joins(:user)
      .where(day: today.iso8601..'2100-12-31')
      .joins('CROSS JOIN LATERAL (SELECT users.event_id AS id UNION SELECT unnest(users.secondary_event_ids)) sports')
    relation = relation.where('sports.id = ?', event.id) if event
    relation = relation.where(users: { prefecture_id: prefecture.id }) if prefecture
    relation
      .group('sports.id', 'users.prefecture_id')
      .pluck('sports.id', 'users.prefecture_id')
  end
end
