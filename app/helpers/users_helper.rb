module UsersHelper
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
