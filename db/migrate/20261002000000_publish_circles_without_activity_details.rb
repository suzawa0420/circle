class PublishCirclesWithoutActivityDetails < ActiveRecord::Migration[8.1]
  # Freeze the publication rule for this backfill and avoid model callbacks,
  # timestamps, counters and moderation changes on existing circles.
  class Circle < ActiveRecord::Base
    self.table_name = "users"
  end

  def up
    sanitizer = ActionView::Base.full_sanitizer
    Circle.where(publication_status: "draft").find_each do |circle|
      next if circle.area.present? && circle.schedule.present?
      next if [circle.name, circle.event_id, circle.prefecture_id, circle.switch].any?(&:blank?)
      body = sanitizer.sanitize(circle.appeal.to_s).gsub(/[[:space:]]/, "")
      next if body.length < 100

      circle.update_columns(publication_status: "published")
    end
  end

  def down
    Circle.where(publication_status: "published").find_each do |circle|
      next if circle.area.present? && circle.schedule.present?

      circle.update_columns(publication_status: "draft")
    end
  end
end
