require 'yaml'
require 'digest'

module AffiliateAdsHelper
  # Public, reviewed campaign configuration; changes take effect on deployment.
  AFFILIATE_ADS = YAML.safe_load_file(Rails.root.join('config/affiliate_ads.yml')).map do |id, attributes|
    attributes.merge('id' => id).freeze
  end.freeze

  def affiliate_ad_for_event(event, placement:)
    return unless event

    affiliate_ad_for_genres([event.ruby], placement)
  end

  def affiliate_ad_for_member(member)
    affiliate_ad_for_genres(member.events.pluck(:ruby), 'participant_mypage')
  end

  def affiliate_ad_cache_key(ad)
    ad && Digest::SHA256.hexdigest(ad.to_json)
  end

  # Positions are one-based and counted across the entire displayed results page.
  def affiliate_ad_insert_after?(position, total:)
    total.positive? && position == [2, total].min
  end

  private

  def affiliate_ad_for_genres(genres, placement)
    AFFILIATE_ADS.find do |ad|
      ad['enabled'] == true && ad['approved'] == true &&
        ad.fetch('placements').include?(placement) && (ad.fetch('events') & genres).any?
    end
  end
end
