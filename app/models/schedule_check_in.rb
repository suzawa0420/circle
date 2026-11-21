class ScheduleCheckIn < ApplicationRecord
  belongs_to :schedule

  def self.today
    Time.current.in_time_zone('Tokyo').to_date.iso8601
  end

  def self.accepting(schedules)
    schedules.where(day: today).where.not(recruitment: '中止')
      .or(schedules.where(day: today, recruitment: nil))
  end

  def self.eligible_answers(schedule)
    schedule.name_schedules.where(answer: 1).joins(:name)
  end
end
