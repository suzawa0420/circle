class AddPublicIdToConversations < ActiveRecord::Migration[8.1]
  def up
    add_column :conversations, :public_id, :string, limit: 24
    add_index :conversations, :public_id, unique: true
    conversation = Class.new(ActiveRecord::Base) { self.table_name = 'conversations' }
    conversation.reset_column_information
    conversation.find_each do |record|
      loop do
        candidate = SecureRandom.alphanumeric(24)
        next if candidate.match?(/\A\d+\z/) || conversation.exists?(public_id: candidate)
        record.update_columns(public_id: candidate)
        break
      end
    end
    change_column_null :conversations, :public_id, false
  end

  def down
    remove_column :conversations, :public_id
  end
end
