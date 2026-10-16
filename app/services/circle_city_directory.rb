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
    cities = City.where(id: UsersCity.where(user_id: population.select(:id)).select(:city_id))
      .where.not(city_kana: [nil, '', 'nil']).includes(:prefecture).to_a
    cities.select! { |city| city.prefecture && city.prefecture.kana.present? && city.prefecture.kana != 'nil' }
    cities.each { |city| yield path(city) }
    Event.where.not(ruby: [nil, '', 'nil']).find_each do |event|
      city_ids = UsersCity.where(user_id: population.for_event(event.id).select(:id)).distinct.pluck(:city_id)
      city_ids = city_ids.to_set
      cities.each { |city| yield path(city, event: event) if city_ids.include?(city.id) }
    end
  end
end
