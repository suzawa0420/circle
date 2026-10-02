class CreateCircleActivityFingerprints < ActiveRecord::Migration[8.1]
  def change
    create_table :circle_activity_fingerprints do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      t.string :fingerprint, null: false
      t.index [:user_id, :kind, :fingerprint], unique: true, name: 'index_circle_activity_fingerprints_unique'
    end
  end
end
