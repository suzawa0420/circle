class CircleProfileCompletionReward
  POINTS = 5

  # Read stored image identifiers, never default URLs or remote image contents.
  def self.items(user)
    introduction = text(user.appeal)
    [
      { label: 'ヘッダー画像', anchor: 'img_field_header', complete: user[:pic_header].present? },
      { label: 'プロフィール画像', anchor: 'img_field_profile', complete: user[:pic_profile].present? },
      { label: "サークルの紹介文（#{User::MINIMUM_APPEAL_LENGTH}文字以上）", anchor: 'circle-introduction', complete: introduction.length >= User::MINIMUM_APPEAL_LENGTH },
      { label: '活動エリア・場所', anchor: 'user_area', complete: user.prefecture_id.present? && text(user.area).present? },
      { label: '活動の曜日・時間帯', anchor: 'user_schedule', complete: text(user.schedule).present? },
      { label: '募集するメンバー・参加条件', anchor: 'user_recruitment', complete: text(user.recruitment).present? },
      { label: '参加費（無料の場合も入力）', anchor: 'user_cost', complete: text(user.cost).present? }
    ]
  end

  def self.missing_items(user)
    items(user).reject { |item| item[:complete] }
  end

  def self.grant(user)
    return false if user.profile_completion_rewarded_at.present? || missing_items(user).any?

    user.with_lock do
      next false if user.profile_completion_rewarded_at.present? || missing_items(user).any?

      user.profile_completion_rewarded_at = Time.current
      CircleScoreUpdater.new.refresh(user)
      # Keep ranking points in sync immediately; the bonus is part of every
      # subsequent recalculation. Do not refresh activity/ranking timestamps.
      user.update_columns(profile_completion_rewarded_at: user.profile_completion_rewarded_at, cb_point: user.cb_point)
      true
    end
  end

  def self.text(value)
    CGI.unescapeHTML(ActionView::Base.full_sanitizer.sanitize(value.to_s)).gsub(/[[:space:]\u200B-\u200D\uFEFF]/, '')
  end
  private_class_method :text
end
