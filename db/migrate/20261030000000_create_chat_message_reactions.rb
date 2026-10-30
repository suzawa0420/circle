class CreateChatMessageReactions < ActiveRecord::Migration[8.1]
  def up
    execute "SET LOCAL lock_timeout = '5s'"
    create_table :chat_message_reactions do |t|
      t.references :chat_message, null: false, foreign_key: { on_delete: :cascade }
      t.references :member, foreign_key: { on_delete: :cascade }
      t.references :admin_user, foreign_key: { on_delete: :cascade }
      t.string :key, null: false, limit: 16
      t.timestamps
      t.index [:chat_message_id, :member_id], unique: true, where: 'member_id IS NOT NULL', name: 'chat_reactions_member_unique'
      t.index [:chat_message_id, :admin_user_id], unique: true, where: 'admin_user_id IS NOT NULL', name: 'chat_reactions_owner_unique'
      t.check_constraint '(member_id IS NOT NULL) <> (admin_user_id IS NOT NULL)', name: 'chat_reactions_one_account'
      t.check_constraint "key IN ('understood', 'thanks', 'checked', 'like', 'excited')", name: 'chat_reactions_key_valid'
    end
  end

  def down
    execute "SET LOCAL lock_timeout = '5s'"
    drop_table :chat_message_reactions
  end
end
