module MatchesHelper
  def match_listing_heading
    location = @prefecture ? "#{@prefecture.name}の" : ''
    sport = @event ? "#{@event.name}の" : ''
    "#{location}#{sport}対戦相手・練習試合の募集"
  end

  def match_circle_updated_on(user)
    user.user_time.to_date if user.user_time.present?
  rescue ArgumentError
    nil
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
