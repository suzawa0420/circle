module UsersHelper
  def circle_deletion_confirmation(user)
    "「#{user.name}」を削除してもよろしいですか？\nこのサークルに紐づくブログ・スケジュール・口コミ・メッセージなどもすべて削除され、元に戻せません。"
  end

  def circle_contact_warning?(user)
    user.is_a?(User) && [1, 2].include?(user.admin_user&.check)
  end

  def circle_contact_warning_options(user)
    return {} unless circle_contact_warning?(user)

    { data: { circle_contact_warning: true }, aria: { haspopup: 'dialog', controls: 'circle-contact-warning' } }
  end

  # Stored scores use tenths. Normalize float noise before splitting the level
  # and its progress, without changing or capping the stored score.
  def circle_level_status(user)
    tenths = [(user.cb_point.to_f * 10).round, 0].max
    level = [tenths / 10, 100].min
    maximum = level == 100
    { level: level, maximum: maximum,
      progress: maximum ? 100 : (tenths % 10) * 10,
      remaining: maximum ? 0.0 : (10 - tenths % 10) / 10.0 }
  end
end
