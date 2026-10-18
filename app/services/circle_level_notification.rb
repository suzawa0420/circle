# A shared DB baseline makes the notification one-time across devices and tabs.
# A nil baseline establishes the current level without celebrating past activity.
class CircleLevelNotification
  def self.consume(user, level:, without_bonus_level: level)
    level = level.clamp(0, 100)
    User.transaction do
      circle = User.where(id: user.id)
      previous, rewarded_at, notified_at = circle.lock.pick(:last_seen_circle_level, :profile_completion_rewarded_at, :profile_completion_notified_at)
      bonus_pending = rewarded_at.present? && notified_at.nil?
      changes = {}
      changes[:last_seen_circle_level] = level if previous != level
      changes[:profile_completion_notified_at] = Time.current if bonus_pending
      circle.update_all(changes) if changes.any?
      if bonus_pending
        from = previous.nil? || previous > level ? without_bonus_level : previous
        { from: from, to: level, profile_completion_bonus: true }
      elsif !previous.nil? && level > previous
        { from: previous, to: level }
      end
    end
  end
end
