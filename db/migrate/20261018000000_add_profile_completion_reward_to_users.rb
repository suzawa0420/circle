class AddProfileCompletionRewardToUsers < ActiveRecord::Migration[8.1]
  def up
    execute "SET LOCAL lock_timeout = '5s'"
    add_column :users, :profile_completion_rewarded_at, :datetime
    add_column :users, :profile_completion_notified_at, :datetime
  end

  def down
    execute "SET LOCAL lock_timeout = '5s'"
    remove_column :users, :profile_completion_notified_at
    remove_column :users, :profile_completion_rewarded_at
  end
end
