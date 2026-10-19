class CreateConversationNotes < ActiveRecord::Migration[8.1]
  def change
    execute "SET LOCAL lock_timeout = '5s'"
    create_table :conversation_notes do |t|
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }
      t.references :member, foreign_key: { on_delete: :cascade }
      t.references :admin_user, foreign_key: { on_delete: :cascade }
      t.string :body, limit: 300, default: '', null: false
      t.timestamps
      t.index [:conversation_id, :member_id], unique: true, where: 'member_id IS NOT NULL', name: 'conversation_notes_member_unique'
      t.index [:conversation_id, :admin_user_id], unique: true, where: 'admin_user_id IS NOT NULL', name: 'conversation_notes_owner_unique'
      t.check_constraint '(member_id IS NOT NULL) <> (admin_user_id IS NOT NULL)', name: 'conversation_notes_one_account'
    end
  end
end
