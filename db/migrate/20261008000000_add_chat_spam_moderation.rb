class AddChatSpamModeration < ActiveRecord::Migration[8.1]
  def change
    add_column :chat_messages, :moderation_status, :string, null: false, default: 'delivered'
    add_column :chat_messages, :spam_score, :integer, null: false, default: 0
    add_column :chat_messages, :spam_reasons, :jsonb, null: false, default: []
    add_column :chat_messages, :spam_fingerprint, :string
    add_column :chat_messages, :reviewed_at, :datetime
    add_column :chat_messages, :released_at, :datetime
    add_column :chat_messages, :recipient_read_at, :datetime
    add_index :chat_messages, [:moderation_status, :created_at]
    add_index :chat_messages, :spam_fingerprint
    add_check_constraint :chat_messages, "moderation_status IN ('delivered', 'held', 'approved', 'spam')", name: 'chat_messages_moderation_valid'
    create_table :chat_spam_destinations do |t|
      t.string :destination, null: false
      t.timestamps
    end
    add_index :chat_spam_destinations, :destination, unique: true
  end
end
