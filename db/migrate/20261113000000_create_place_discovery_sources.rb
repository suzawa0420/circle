class CreatePlaceDiscoverySources < ActiveRecord::Migration[8.1]
  def change
    create_table :place_discovery_sources do |t|
      t.string :prefecture_name, null: false
      t.string :root_url, null: false
      t.text :state
      t.datetime :last_checked_at
      t.string :last_status
      t.timestamps
    end
    add_index :place_discovery_sources, :prefecture_name, unique: true
  end
end
