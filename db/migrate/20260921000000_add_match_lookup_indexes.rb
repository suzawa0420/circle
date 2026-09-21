class AddMatchLookupIndexes < ActiveRecord::Migration[6.0]
  disable_ddl_transaction!

  def change
    add_index :matches, [:recruit, :updated_at], algorithm: :concurrently
    add_index :matches, [:user_id, :updated_at], algorithm: :concurrently
  end
end
