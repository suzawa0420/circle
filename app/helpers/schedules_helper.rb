module SchedulesHelper
  SCHEDULE_WEEKDAYS = %w[日 月 火 水 木 金 土].freeze

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
