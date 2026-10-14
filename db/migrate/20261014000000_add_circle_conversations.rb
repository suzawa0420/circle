class AddCircleConversations < ActiveRecord::Migration[8.1]
  def change
    # Fail safely instead of waiting indefinitely for a busy conversation table.
    reversible do |direction|
      direction.up do
        execute "SET LOCAL lock_timeout = '5s'"
        execute "SET LOCAL statement_timeout = '30s'"
      end
    end
    change_column_null :conversations, :member_id, true
    add_reference :conversations, :source_user, foreign_key: { to_table: :users }
    add_check_constraint :conversations,
      '(member_id IS NOT NULL AND source_user_id IS NULL) OR (member_id IS NULL AND source_user_id IS NOT NULL AND source_user_id <> user_id)',
      name: 'conversations_one_sender_kind'
    add_index :conversations, 'LEAST(user_id, source_user_id), GREATEST(user_id, source_user_id)',
      unique: true, where: 'source_user_id IS NOT NULL', name: 'index_conversations_circle_pair'
  end
end
