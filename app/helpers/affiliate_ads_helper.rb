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
    affiliate_ad_for_genres(member.events.pluck(:ruby), 'participant_mypage', audience: 'participant')
  end

  def affiliate_ad_for_organizer(circle)
    return unless admin_user_signed_in? && current_admin_user.id == circle.admin_user_id

    affiliate_ad_for_genres([circle.event&.ruby].compact, 'organizer_mypage', audience: 'organizer')
  end

  def affiliate_ad_cache_key(ad)
    ad && Digest::SHA256.hexdigest(ad.to_json)
  end

  # Positions are one-based and counted across the entire displayed results page.
  def affiliate_ad_insert_after?(position, total:)
    total.positive? && position == [2, total].min
  end

  private

  def affiliate_ad_for_genres(genres, placement, audience: 'public')
    AFFILIATE_ADS.find do |ad|
      ad['enabled'] == true && ad['approved'] == true &&
        ad.fetch('audiences', %w[public participant organizer]).include?(audience) &&
        ad.fetch('placements').include?(placement) && (ad.fetch('events') & genres).any?
    end
  end
end
