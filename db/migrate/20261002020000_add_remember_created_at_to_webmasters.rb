class AddRememberCreatedAtToWebmasters < ActiveRecord::Migration[8.1]
  def change
    add_column :webmasters, :remember_created_at, :datetime
  end
end
