# Page-local data for the two public circle listings. Never preload every review
# or schedule: a popular circle may have years of history in those tables.
class CircleListingData
  attr_reader :users

  def initialize(relation)
    retained_includes = relation.includes_values.flatten - [:reviews, :schedules, :tags]
    # Keep joins needed by existing filters/order, but explicitly preload the
    # display associations. includes would join tags into prefecture-sorted
    # listings, interfering with ordered tags and LIMIT/OFFSET pagination.
    @users = relation.except(:includes)
    @users = @users.includes(*retained_includes) if retained_includes.any?
    @users = @users.preload(:event, :prefecture, :prefecture_sub, :listing_tags)
  end

  def review_count(user)
    review_counts.fetch(user.id, 0)
  end

  def schedules_for(user)
    upcoming_schedules.fetch(user.id, [])
  end

  private

  def review_counts
    @review_counts ||= Review.where(user_id: users.map(&:id)).group(:user_id).count
  end

  def upcoming_schedules
    @upcoming_schedules ||= begin
      ids = users.select { |user| user.switch == '募集中' }.map(&:id).uniq
      if ids.empty?
        {}
      else
        # PostgreSQL LATERAL limits each indexed user lookup before loading Ruby
        # objects. The total returned is at most two schedules per visible user.
        Schedule.find_by_sql([<<~SQL, ids, DateTime.yesterday]).group_by(&:user_id)
          SELECT upcoming.*
          FROM (SELECT id FROM users WHERE id IN (?)) AS listing_users
          CROSS JOIN LATERAL (
            SELECT schedules.* FROM schedules
            WHERE schedules.user_id = listing_users.id AND schedules.day > ?
            ORDER BY schedules.day ASC, schedules.id ASC
            LIMIT 2
          ) AS upcoming
          ORDER BY upcoming.user_id ASC, upcoming.day ASC, upcoming.id ASC
        SQL
      end
    end
  end
end
