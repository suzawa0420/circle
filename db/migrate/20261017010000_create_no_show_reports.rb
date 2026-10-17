class CreateNoShowReports < ActiveRecord::Migration[8.1]
  def change
    create_table :no_show_reports do |t|
      t.references :conversation, null: false, foreign_key: true
      t.datetime :scheduled_at, null: false
      t.boolean :participation_confirmed, default: false, null: false
      t.boolean :no_advance_notice, default: false, null: false
      t.text :confirmation_details, null: false
      t.text :details, null: false
      t.text :member_response
      t.datetime :member_responded_at
      t.string :status, default: 'pending', null: false
      t.text :operational_memo
      t.timestamps
    end
    add_index :no_show_reports, [:conversation_id, :scheduled_at], unique: true
    add_index :no_show_reports, :status
    add_check_constraint :no_show_reports, "status IN ('pending', 'confirmed', 'dismissed')", name: 'no_show_reports_valid_status'
  end
end
