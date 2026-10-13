class CreateBacklinkRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :backlink_requests do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :placement_url, null: false, limit: 2048
      t.string :status, null: false, default: 'pending'
      t.text :review_note
      t.references :reviewed_by, foreign_key: { to_table: :webmasters }
      t.datetime :submitted_at, null: false
      t.datetime :approved_at
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :backlink_requests, [:status, :submitted_at]
    add_check_constraint :backlink_requests, "status IN ('pending', 'approved', 'rejected', 'revoked')", name: 'backlink_requests_status'
  end
end
