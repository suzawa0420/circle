# Read the populated public regions once instead of querying the circle
# publication policy separately for each sport while the site serves traffic.
class CircleSitemapLandings
  URLS = Rails.application.routes.url_helpers

  def self.each_path
    return enum_for(__method__) unless block_given?

    populations = User.publicly_visible.distinct.pluck(:event_id, :prefecture_id, :prefecture_sub_id)
    sports = populations.group_by(&:first)
    prefectures = Prefecture.where.not(kana: [nil, '', 'nil']).index_by(&:id)

    Event.where(id: sports.keys.compact).where.not(ruby: [nil, '', 'nil']).find_each do |event|
      yield URLS.event_path(event.ruby), 0.8
      ids = sports.fetch(event.id).flat_map { |_, primary_id, secondary_id| [primary_id, secondary_id] }
      ids.compact.uniq.sort.each do |id|
        prefecture = prefectures[id]
        yield URLS.event_prefecture_path(event.ruby, prefecture.kana), 0.8 if prefecture
      end
    end

    # Preserve the primary-only rule for the unfiltered prefecture landing.
    populations.map { |_, primary_id, _| primary_id }.compact.uniq.sort.each do |id|
      prefecture = prefectures[id]
      yield URLS.prefecture_path(prefecture.kana), 0.8 if prefecture
    end
  end
end
