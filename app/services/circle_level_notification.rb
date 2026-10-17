# A shared DB baseline makes the notification one-time across devices and tabs.
# A nil baseline establishes the current level without celebrating past activity.
class CircleLevelNotification
  def self.consume(user, level:)
    level = level.clamp(0, 100)
    User.transaction do
      circle = User.where(id: user.id)
      previous = circle.lock.pick(:last_seen_circle_level)
      circle.update_all(last_seen_circle_level: level) if previous != level
      { from: previous, to: level } if !previous.nil? && level > previous
    end
  end
end
