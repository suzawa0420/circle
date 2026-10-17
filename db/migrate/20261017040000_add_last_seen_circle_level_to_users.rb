class AddLastSeenCircleLevelToUsers < ActiveRecord::Migration[8.1]
  def up
    execute "SET LOCAL lock_timeout = '5s'"
    add_column :users, :last_seen_circle_level, :integer
  end

  def down
    execute "SET LOCAL lock_timeout = '5s'"
    remove_column :users, :last_seen_circle_level
  end
end
