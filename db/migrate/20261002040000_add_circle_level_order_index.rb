class AddCircleLevelOrderIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :users,
      'switch ASC, LEAST(100, GREATEST(0, FLOOR(ROUND(cb_point::numeric, 1)))) DESC, last_post DESC, id DESC',
      name: 'index_users_on_circle_level_order', algorithm: :concurrently
  end

  def down
    remove_index :users, name: 'index_users_on_circle_level_order', algorithm: :concurrently
  end
end
