class AddModerationReasons < ActiveRecord::Migration[8.1]
  def change
    [:users, :blogs].each do |table|
      add_column table, :moderation_reasons, :jsonb, null: false, default: []
      add_column table, :moderation_checked_at, :datetime
    end
  end
end
