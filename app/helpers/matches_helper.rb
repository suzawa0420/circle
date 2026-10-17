module MatchesHelper
  def match_listing_heading
    location = @prefecture ? "#{@prefecture.name}の" : ''
    sport = @event ? "#{@event.name}の" : ''
    "#{location}#{sport}対戦相手・練習試合の募集"
  end

  def match_updated_at(matching)
    circle_updated_at = begin
      Time.zone.parse(matching.user.user_time) if matching.user.user_time.present?
    rescue ArgumentError, TypeError
      nil
    end
    [matching.updated_at, circle_updated_at].compact.max&.in_time_zone
  end

  def match_page_structured_data(matching)
    return unless public_structured_data_page? && matching.user.publicly_visible?
    url = "https://circle-book.com#{match_path(matching.user_id)}"
    {
      '@type' => 'WebPage', '@id' => url, 'url' => url,
      'name' => "#{matching.user.name}の対戦相手・練習試合の募集",
      'dateModified' => match_updated_at(matching)&.iso8601,
      'description' => structured_text(matching.comment).presence,
      'about' => { '@type' => 'Organization', '@id' => circle_schema_id(matching.user), 'name' => matching.user.name.to_s }
    }.compact
  end

  def match_avatar(user, detail: false)
    if user.pic_profile.present?
      image_tag user.pic_profile.url, class: 'match-directory__avatar', alt: '',
        width: 80, height: 80, loading: detail ? 'eager' : 'lazy', decoding: 'async'
    else
      circle_avatar_tag user, class: 'match-directory__avatar'
    end
  end
end
