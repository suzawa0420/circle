require 'set'

# City landing pages are backed by explicitly registered activity areas, rather
# than nationwide circles which happen to appear in every legacy area search.
class CircleCityDirectory
  URLS = Rails.application.routes.url_helpers

  def self.users(city, event: nil)
    users = User.publicly_visible.where(id: UsersCity.where(city_id: city.id).select(:user_id))
    event ? users.for_event(event.id) : users
  end

  def self.populated_cities(prefecture, event: nil)
    users = User.publicly_visible
    users = users.for_event(event.id) if event
    prefecture.cities.where(id: UsersCity.where(user_id: users.select(:id)).select(:city_id))
      .where.not(city_kana: [nil, '', 'nil']).order(:id)
  end

  def self.path(city, event: nil, prefecture: city.prefecture)
    if event
      URLS.event_prefecture_city_path(event.ruby, prefecture.kana, city.city_kana)
    else
      URLS.prefecture_city_path(prefecture.kana, city.city_kana)
    end
  end

  def self.each_populated_path
    return enum_for(__method__) unless block_given?

    population = User.publicly_visible
    city_pairs = UsersCity.joins(:user).merge(population).distinct
      .pluck('users.event_id', 'users_cities.city_id')
    by_sport = city_pairs.group_by(&:first)
    cities = City.where(id: city_pairs.map(&:last).uniq)
      .where.not(city_kana: [nil, '', 'nil']).includes(:prefecture).order(:id).to_a
    cities.select! { |city| city.prefecture && city.prefecture.kana.present? && city.prefecture.kana != 'nil' }
    cities.each { |city| yield path(city) }
    city_by_id = cities.index_by(&:id)
    Event.where(id: by_sport.keys.compact).where.not(ruby: [nil, '', 'nil']).find_each do |event|
      by_sport.fetch(event.id).map(&:last).compact.sort.each do |city_id|
        city = city_by_id[city_id]
        yield path(city, event: event) if city
      end
    end
  end
end
