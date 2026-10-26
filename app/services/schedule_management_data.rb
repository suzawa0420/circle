class ScheduleManagementData
  attr_reader :past

  def initialize(user:, past: false, page: nil, schedule: nil)
    @user, @past, @page, @schedule = user, past, page, schedule
  end

  def schedules
    @schedules ||= @user.schedules.where(past ? 'day < ?' : 'day >= ?', Date.current.iso8601)
      .order(day: past ? :desc : :asc, time_s: :asc, id: :asc).page(@page).per(20)
  end

  def count(schedule, answer)
    counts.fetch([schedule.id, answer], 0)
  end

  def unanswered(schedule)
    [member_count - count(schedule, 1) - count(schedule, 0), 0].max
  end

  private

  def counts
    @counts ||= NameSchedule.where(schedule_id: @schedule ? [@schedule.id] : schedules.map(&:id))
      .group(:schedule_id, :answer).count
  end

  def member_count
    @member_count ||= Name.joins(:schedules).where(schedules: { user_id: @user.id }).distinct.count
  end
end
