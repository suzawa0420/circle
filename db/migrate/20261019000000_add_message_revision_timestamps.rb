class AddMessageRevisionTimestamps < ActiveRecord::Migration[8.1]
  def change
    execute "SET LOCAL lock_timeout = '5s'"
    add_column :chat_messages, :edited_at, :datetime
    add_column :chat_messages, :deleted_at, :datetime
  end
end
