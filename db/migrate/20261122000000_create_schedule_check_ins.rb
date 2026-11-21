class CreateScheduleCheckIns < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :attendance_check_in_token, :string
    add_index :users, :attendance_check_in_token, unique: true

    create_table :schedule_check_ins do |t|
      t.references :schedule, null: false, foreign_key: { on_delete: :cascade }, index: false
      # Keep the historical record even when an existing RSVP or name is removed.
      t.bigint :name_id, null: false
      t.string :display_name, null: false
      t.datetime :checked_in_at, null: false
      t.index [:schedule_id, :name_id], unique: true
    end
  end
end
