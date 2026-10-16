class AddPeerReviewNotifications < ActiveRecord::Migration[8.1]
  def change
    %w[member owner].each do |role|
      add_column :conversations, "#{role}_review_invited_at", :datetime
      add_column :conversations, "#{role}_review_notification_due_at", :datetime
      add_column :conversations, "#{role}_review_notified_at", :datetime
      add_index :conversations, "#{role}_review_notification_due_at",
                where: "#{role}_review_notification_due_at IS NOT NULL"
    end
  end
end
