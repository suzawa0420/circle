class EventDayListing
  attr_reader :date, :now

  def self.path(date)
    "/dates/#{date.year}/#{date.month}/#{date.day}"
  end

  def self.public_schedules
    Schedule.where(user_id: User.publicly_visible.select(:id))
  end

  def initialize(date:, event: nil, prefecture: nil, sort: nil, now: Time.current)
    @date = date
    @now = now.in_time_zone('Tokyo')
    @sort = sort
    @base = self.class.public_schedules.where(day: date.iso8601)
    @base = @base.where(user_id: User.where(event_id: event.id).select(:id)) if event
    @base = @base.where(user_id: User.where(prefecture_id: prefecture.id).select(:id)) if prefecture
  end

  def total_count
    @total_count ||= @base.count
  end

  def schedules
    counts = NameSchedule.where(answer: 1, schedule_id: @base.select(:id))
      .group(:schedule_id).select('schedule_id, COUNT(*) AS accepted_count').to_sql
    connection = Schedule.connection
    # Rails stores time columns in UTC; compare/sort clock times in Japan,
    # including morning activities whose UTC clock is on the previous day.
    start_clock = "(schedules.time_s + interval '9 hours')::time"
    end_clock = "(schedules.time_e + interval '9 hours')::time"
    closed = "schedules.recruitment IN ('中止', '募集終了') OR (schedules.recruitment_numbers > 0 AND COALESCE(attendance.accepted_count, 0) >= schedules.recruitment_numbers)"
    ended = if date < now.to_date
      'TRUE'
    elsif date == now.to_date
      # An end earlier than the start is an overnight event, not an ended event.
      "schedules.time_e IS NOT NULL AND (schedules.time_s IS NULL OR #{end_clock} >= #{start_clock}) AND #{end_clock} <= #{connection.quote(now.strftime('%H:%M:%S'))}::time"
    else
      'FALSE'
    end
    order = case @sort
    when '2' then 'schedules.created_at DESC, schedules.id DESC'
    when '3' then "#{start_clock} ASC NULLS LAST, schedules.id ASC"
    else "md5(schedules.id::text || #{connection.quote(now.to_date.iso8601)}), schedules.id ASC"
    end
    # ImageUploader appends updated_at to stored image URLs for cache busting.
    columns = (ScheduleListingData::COLUMNS + [:top_image, :updated_at]).map { |column| "schedules.#{column}" }
    @base.joins("LEFT JOIN (#{counts}) attendance ON attendance.schedule_id = schedules.id")
      .select(*columns, 'COALESCE(attendance.accepted_count, 0) AS accepted_count', "(#{ended}) AS event_ended")
      .preload(user: [{ event: :category }, :prefecture])
      .order(Arel.sql("CASE WHEN (#{closed}) OR (#{ended}) THEN 1 ELSE 0 END ASC, #{order}"))
  end

  def status(schedule)
    return ['cancelled', '中止'] if schedule.recruitment == '中止'
    return ['ended', '開催終了'] if schedule[:event_ended]
    remaining = schedule.recruitment_numbers.to_i - schedule[:accepted_count].to_i
    limited = schedule.recruitment_numbers.to_i.positive?
    return ['full', '満員'] if schedule.recruitment == '募集終了' || (limited && remaining <= 0)
    return ['few', '残りわずか'] if limited && remaining <= 3
    ['open', '募集中']
  end
end
