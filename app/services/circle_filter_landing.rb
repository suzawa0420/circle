require 'set'

# Fixed, server-rendered URLs for one recruitment group and one age band.
# Keyword searches and multi-select filters remain internal searches.
class CircleFilterLanding
  URLS = Rails.application.routes.url_helpers

  def self.path(event: nil, prefecture: nil, group: nil, age: nil)
    unless group || age
      return URLS.event_prefecture_path(event.ruby, prefecture.kana) if event && prefecture
      return URLS.event_path(event.ruby) if event
      return URLS.prefecture_path(prefecture.kana) if prefecture
      return URLS.circles_path
    end
    URLS.circle_filter_landing_path(activity: event&.ruby || 'all', region: prefecture&.kana || 'all',
      group: group&.id || 'all', age: age&.id || 'all')
  end

  def self.from_search(params)
    return unless params[:detailed] == '1' && params[:q].blank?
    return if %i[category_id city_id tag_id].any? { |key| params[key].present? }
    groups = Array(params[:group_ids]).reject(&:blank?).uniq
    ages = Array(params[:age_ids]).reject(&:blank?).uniq
    return if groups.size > 1 || ages.size > 1
    path(event: params[:event_id].present? ? Event.find(params[:event_id]) : nil,
      prefecture: params[:prefecture_id].present? ? Prefecture.find(params[:prefecture_id]) : nil,
      group: groups.any? ? Group.find(groups.first) : nil,
      age: ages.any? ? Age.find(ages.first) : nil)
  end

  # Aggregate the registered combinations once, rather than issuing a search
  # for every theoretical combination. Null dimensions represent 'all'.
  def self.each_populated_path
    return enum_for(__method__) unless block_given?
    events = Event.all.index_by(&:id)
    prefectures = Prefecture.all.index_by(&:id)
    groups = Group.all.index_by(&:id)
    ages = Age.all.index_by(&:id)
    population = User.publicly_visible.select(:id, :event_id, :prefecture_id, :prefecture_sub_id).to_sql
    sql = <<~SQL
      WITH public_users AS (#{population}), combinations AS (
        SELECT u.event_id, area.id AS prefecture_id, g.id AS group_id, a.id AS age_id
        FROM public_users u
        JOIN LATERAL (
          SELECT u.prefecture_id AS id
          UNION SELECT u.prefecture_sub_id WHERE u.prefecture_sub_id IS NOT NULL
        ) area ON true
        LEFT JOIN users_groups ug ON ug.user_id = u.id
        LEFT JOIN groups g ON g.id = ug.group_id
        LEFT JOIN users_ages ua ON ua.user_id = u.id
        LEFT JOIN ages a ON a.id = ua.age_id
      )
      SELECT event_id, prefecture_id, group_id, age_id
      FROM combinations
      GROUP BY CUBE (event_id, prefecture_id, group_id, age_id)
      HAVING group_id IS NOT NULL OR age_id IS NOT NULL
    SQL
    seen = Set.new
    User.connection.select_all(sql).each do |row|
      event = events[row['event_id']]
      prefecture = prefectures[row['prefecture_id']]
      next if row['event_id'] && (!event || event.ruby.blank? || event.ruby == 'nil')
      next if row['prefecture_id'] && (!prefecture || prefecture.kana.blank? || prefecture.kana == 'nil')
      url = path(event: event, prefecture: prefecture, group: groups[row['group_id']], age: ages[row['age_id']])
      yield url if seen.add?(url)
    end
  end
end
