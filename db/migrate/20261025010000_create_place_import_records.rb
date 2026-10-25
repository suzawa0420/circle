class CreatePlaceImportRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :place_import_runs do |t|
      t.string :source, null: false
      t.string :mode, null: false
      t.string :status, null: false, default: 'running'
      t.text :summary
      t.timestamps
    end
    create_table :place_import_candidates do |t|
      t.string :source, null: false
      t.string :source_url, null: false
      t.string :fingerprint, null: false
      t.string :status, null: false, default: 'pending'
      t.text :payload, null: false
      t.text :reason
      t.references :place, foreign_key: true
      t.references :place_import_run, foreign_key: true
      t.datetime :checked_at, null: false
      t.timestamps
    end
    add_index :place_import_candidates, [:source, :fingerprint], unique: true
    add_index :place_import_candidates, [:status, :updated_at]
  end
end
