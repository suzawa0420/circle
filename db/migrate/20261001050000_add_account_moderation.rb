class AddAccountModeration < ActiveRecord::Migration[8.1]
  def up
    [:members, :admin_users].each do |table|
      add_column table, :suspended_at, :datetime
      add_column table, :suspension_reason, :text
    end
    add_column :chat_reports, :status, :string, null: false, default: 'pending'
    add_column :chat_reports, :operational_memo, :text
    execute "UPDATE chat_reports SET status = 'resolved' WHERE resolved_at IS NOT NULL"
    add_check_constraint :chat_reports, "status IN ('pending', 'in_progress', 'resolved')", name: 'chat_reports_status_valid'
  end
  def down
    remove_check_constraint :chat_reports, name: 'chat_reports_status_valid'
    remove_column :chat_reports, :operational_memo
    remove_column :chat_reports, :status
    [:members, :admin_users].each do |table|
      remove_column table, :suspended_at
      remove_column table, :suspension_reason
    end
  end
end
