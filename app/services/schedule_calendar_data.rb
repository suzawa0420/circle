class ScheduleCalendarData
  COLUMNS = ScheduleListingData::COLUMNS

  attr_reader :month, :selected_date, :today, :past_page

  def initialize(user:, month: nil, date: nil, past: false, page: nil, today: Date.current)
    @user = user
    @today = today
    @month = month.present? ? parse_month(month) : today.beginning_of_month
    @selected_date = parse_date(date) if date.present?
    if @selected_date && !(@month..@month.end_of_month).cover?(@selected_date)
      raise ActiveRecord::RecordNotFound
    end
    @past_page = user.schedules.where('day < ?', today.iso8601)
      .select(*COLUMNS).order(day: :desc, time_s: :asc, id: :asc).page(page) if past
  end

  def schedules
    @schedules ||= @user.schedules.select(*COLUMNS)
      .where(day: month.iso8601..month.end_of_month.iso8601)
      .order(day: :asc, time_s: :asc, id: :asc).to_a
  end

  def by_day
    @by_day ||= schedules.group_by { |schedule| Date.iso8601(schedule.day) }
  end

  def visible
    return by_day.fetch(selected_date, []) if selected_date
    return schedules if month < today.beginning_of_month

    schedules.select { |schedule| schedule.day >= today.iso8601 }
  end

  def past
    @past ||= past_page ? past_page.to_a : []
  end

  def accepted_count(schedule)
    accepted_counts.fetch(schedule.id, 0)
  end

  private

  def accepted_counts
    @accepted_counts ||= begin
      ids = (schedules + past).map(&:id).uniq
      ids.empty? ? {} : NameSchedule.where(schedule_id: ids, answer: 1).group(:schedule_id).count
    end
  end

  def parse_month(value)
    raise ActiveRecord::RecordNotFound unless value.is_a?(String) && value.match?(/\A[0-9]{4}-(0[1-9]|1[0-2])\z/)
    date = Date.iso8601("#{value}-01")
    raise ActiveRecord::RecordNotFound unless (1900..2100).cover?(date.year)
    date
  rescue Date::Error
    raise ActiveRecord::RecordNotFound
  end

  def parse_date(value)
    raise ActiveRecord::RecordNotFound unless value.is_a?(String) && value.match?(/\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/)
    Date.iso8601(value)
  rescue Date::Error
    raise ActiveRecord::RecordNotFound
  end
end
