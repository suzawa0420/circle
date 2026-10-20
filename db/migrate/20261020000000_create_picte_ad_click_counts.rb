class CreatePicteAdClickCounts < ActiveRecord::Migration[8.1]
  def change
    create_table :picte_ad_click_counts do |t|
      t.date :recorded_on, null: false
      t.string :placement, null: false
      t.bigint :click_count, null: false, default: 0
    end
    add_index :picte_ad_click_counts, [:recorded_on, :placement], unique: true
    add_check_constraint :picte_ad_click_counts, "placement IN ('search', 'mypage')", name: 'picte_ad_placement'
    add_check_constraint :picte_ad_click_counts, 'click_count >= 0', name: 'picte_ad_click_count_nonnegative'
  end
end
