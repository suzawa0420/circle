class CreateMemberConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :members, :email_verified_at, :datetime
    add_column :members, :verification_sent_at, :datetime

    create_table :conversations do |t|
      t.references :user, null: false, foreign_key: true
      t.references :member, null: false, foreign_key: true
      t.datetime :accepted_at
      t.datetime :review_deadline
      t.datetime :reviews_published_at
      t.boolean :legacy_member_review, null: false, default: false
      t.boolean :member_blocked, null: false, default: false
      t.boolean :owner_blocked, null: false, default: false
      t.string :respond_check
      t.bigint :member_read_message_id, null: false, default: 0
      t.bigint :owner_read_message_id, null: false, default: 0
      t.datetime :member_notification_due_at
      t.datetime :owner_notification_due_at
      t.datetime :member_notified_at
      t.datetime :owner_notified_at
      t.timestamps
    end
    add_index :conversations, :member_notification_due_at
    add_index :conversations, :owner_notification_due_at
    add_index :conversations, [:user_id, :member_id], unique: true
    add_index :conversations, [:reviews_published_at, :review_deadline], name: 'index_conversations_review_publication'

    create_table :chat_messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.string :sender_role, null: false
      t.text :body, null: false
      t.timestamps
    end
    add_index :chat_messages, [:conversation_id, :id]

    create_table :conversation_reviews do |t|
      t.references :conversation, null: false, foreign_key: true
      t.string :author_role, null: false
      t.integer :score, null: false
      t.text :comment, null: false
      t.boolean :participated, null: false, default: false
      t.datetime :published_at
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :conversation_reviews, [:conversation_id, :author_role], unique: true, name: 'index_conversation_reviews_unique_author'
    add_reference :reviews, :conversation_review, foreign_key: true, index: { unique: true }

    create_table :chat_reports do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :chat_message, foreign_key: true
      t.references :conversation_review, foreign_key: true
      t.string :reporter_role, null: false
      t.text :reason, null: false
      t.datetime :resolved_at
      t.timestamps
    end
  end
end
