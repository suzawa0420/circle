require 'digest'

# Keep only fingerprints after deletion, so identical reposts cannot refresh
# ranking time. Existing records are remembered before editing or deletion.
class CircleActivityRecorder
  def self.attributes_for(record, previous: false)
    columns = case record
              when Blog then %w[content]
              when Schedule then %w[day time_s time_e venue]
              when Question then %w[content]
              else raise ArgumentError, 'Unsupported activity'
              end
    columns.to_h do |column|
      [column, previous ? record.attribute_in_database(column) : record.public_send(column)]
    end
  end

  def self.keys_for(record, previous: false)
    values = attributes_for(record, previous: previous).values.map do |value|
      value.is_a?(Time) ? value.strftime('%H:%M:%S') : value.to_s.unicode_normalize(:nfkc).gsub(/\s+/, ' ').strip
    end
    keys = [Digest::SHA256.hexdigest(values.to_json)]
    keys << "question-#{record.id}" if record.is_a?(Question)
    keys
  end

  def self.remember(record, previous: false)
    return if record.is_a?(Question) && (previous ? record.attribute_in_database('answer') : record.answer).blank?
    rows = keys_for(record, previous: previous).map do |key|
      { user_id: record.user_id, kind: record.class.name, fingerprint: key }
    end
    CircleActivityFingerprint.insert_all(rows, unique_by: :index_circle_activity_fingerprints_unique)
  end

  def self.record(record)
    return false if record.is_a?(Question) && record.answer.blank?
    return false if record.is_a?(Blog) && record.moderation_status != 'clear'

    user = record.user
    user.with_lock do
      keys = keys_for(record)
      seen = CircleActivityFingerprint.exists?(user_id: user.id, kind: record.class.name, fingerprint: keys)
      # Also cover live records created before the fingerprint table existed.
      duplicates = record.class.where(user_id: user.id).where(attributes_for(record)).where.not(id: record.id)
      duplicates = duplicates.where.not(answer: [nil, '']) if record.is_a?(Question)
      seen ||= duplicates.exists?
      remember(record)
      next false if seen

      now = Time.current
      ranking_time = user.admin_user.check.present? && user.admin_user.check != 0 ? 5.years.ago : now
      user.update!(user_time: now, last_post: ranking_time)
      true
    end
  end
end
