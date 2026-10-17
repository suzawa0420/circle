class CreateConversationReplyReports < ActiveRecord::Migration[8.1]
  def change
    create_table :conversation_reply_reports do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :chat_message, null: false, foreign_key: true
      t.string :reporter_role, null: false
      t.timestamps
    end
    add_index :conversation_reply_reports, [:conversation_id, :reporter_role], unique: true, name: 'index_reply_reports_on_conversation_and_role'
    add_check_constraint :conversation_reply_reports, "reporter_role IN ('member', 'owner')", name: 'reply_reports_valid_role'
  end
end
