# Data used by the related schedules on a schedule detail page. Keep the full
# upcoming list and existing past pagination, but never load attendance records
# or large schedule bodies just to display a date, title and participant count.
class ScheduleListingData
  COLUMNS = %i[id user_id day time_s time_e recruitment recruitment_numbers venue title].freeze

  attr_reader :past_page

  def initialize(upcoming:, past:, excluded_id:, show_upcoming:)
    @upcoming_relation = upcoming
    @past_page = past.select(*COLUMNS)
    @excluded_id = excluded_id
    @show_upcoming = show_upcoming
  end

  def upcoming
    @upcoming ||= @show_upcoming ? visible(@upcoming_relation.select(*COLUMNS)) : []
  end

  def past
    # Exclude after pagination so page boundaries and total_count stay the same.
    @past ||= visible(past_page)
  end

  def accepted_count(schedule)
    accepted_counts.fetch(schedule.id, 0)
  end

  private

  def visible(relation)
    relation.to_a.reject { |schedule| schedule.id == @excluded_id }
  end

  def accepted_counts
    @accepted_counts ||= begin
      ids = (upcoming + past).map(&:id)
      ids.empty? ? {} : NameSchedule.where(schedule_id: ids, answer: 1).group(:schedule_id).count
    end
  end
end
