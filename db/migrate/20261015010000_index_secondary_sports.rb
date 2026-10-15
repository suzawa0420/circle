class IndexSecondarySports < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :users, :secondary_event_ids, using: :gin, algorithm: :concurrently, if_not_exists: true
  end
end
