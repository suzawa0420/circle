module SchedulesHelper
  SCHEDULE_WEEKDAYS = %w[日 月 火 水 木 金 土].freeze

  def schedule_image_source(schedule, user: schedule.user)
    return schedule.top_image.url if schedule.top_image.present?
    return user.pic_header.url if user.pic_header.present?

    event = user.event
    [["events", event&.ruby], ["categories", event&.category&.kana]].each do |directory, slug|
      next unless slug.to_s.match?(/\A[a-z0-9_-]+\z/)
      path = "/images/#{directory}/#{slug}.jpg"
      return path if File.file?(Rails.root.join('public', path.delete_prefix('/')))
    end
    '/images/events/event.jpg'
  end

  def public_schedule_status(schedule, accepted_count:, now: Time.current)
    now = now.in_time_zone('Tokyo')
    return { key: 'cancelled', label: '中止' } if schedule.recruitment == '中止'
    start_clock = schedule.time_s&.strftime('%H:%M:%S')
    end_clock = schedule.time_e&.strftime('%H:%M:%S')
    ended_today = schedule.day == now.to_date.iso8601 && end_clock &&
      (!start_clock || end_clock >= start_clock) && end_clock <= now.strftime('%H:%M:%S')
    return { key: 'ended', label: '開催終了' } if schedule.day < now.to_date.iso8601 || ended_today
    remaining = schedule.recruitment_numbers.to_i - accepted_count
    limited = schedule.recruitment_numbers.to_i.positive?
    return { key: 'full', label: '満員' } if schedule.recruitment == '募集終了' || (limited && remaining <= 0)
    return { key: 'few', label: '残りわずか' } if limited && remaining <= 3
    { key: 'open', label: '募集中' }
  end

  def calendar_schedule_status(schedule, calendar)
    return { key: 'cancelled', mark: '×', label: '中止' } if schedule.recruitment == '中止'
    return { key: 'ended', mark: '済', label: '開催終了' } if schedule.day < calendar.today.iso8601
    remaining = schedule.recruitment_numbers.to_i - calendar.accepted_count(schedule)
    limited = schedule.recruitment_numbers.to_i.positive?
    if schedule.recruitment == '募集終了' || (limited && remaining <= 0)
      { key: 'full', mark: '満', label: '満員' }
    elsif limited && remaining <= 3
      { key: 'few', mark: '△', label: '残りわずか' }
    else
      { key: 'open', mark: '○', label: '募集中' }
    end
  end

  def calendar_schedule_time(schedule)
    return '時間未定' unless schedule.time_s || schedule.time_e
    [schedule.time_s&.strftime('%H:%M') || '未定', schedule.time_e&.strftime('%H:%M') || '未定'].join('–')
  end

  def calendar_schedule_date(date)
    "#{date.month}月#{date.day}日（#{SCHEDULE_WEEKDAYS[date.wday]}）"
  end
end
