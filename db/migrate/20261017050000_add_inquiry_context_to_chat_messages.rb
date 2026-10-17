class AddInquiryContextToChatMessages < ActiveRecord::Migration[8.1]
  def change
    execute "SET LOCAL lock_timeout = '5s'"
    add_column :chat_messages, :inquiry_context, :jsonb, default: {}, null: false
  end
end
