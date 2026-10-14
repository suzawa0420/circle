class CreatePlaceInformationReports < ActiveRecord::Migration[8.1]
  def change
    create_table :place_information_reports do |t|
      t.references :place, foreign_key: { on_delete: :nullify }
      t.string :place_name, null: false
      t.string :kind, null: false
      t.text :body, null: false
      t.string :reference_url, limit: 2048
      t.string :status, null: false, default: 'pending'
      t.string :submission_key, null: false
      t.text :staff_note
      t.references :reviewed_by, foreign_key: { to_table: :webmasters }
      t.datetime :reviewed_at
      t.datetime :resolved_at
      t.timestamps
    end
    add_index :place_information_reports, :submission_key, unique: true
    add_index :place_information_reports, [:status, :created_at]
    add_check_constraint :place_information_reports, "status IN ('pending', 'in_progress', 'resolved', 'dismissed')", name: 'place_information_reports_status'
    add_check_constraint :place_information_reports, "kind IN ('closed', 'hours', 'price', 'address', 'facility', 'other')", name: 'place_information_reports_kind'
  end
end
