class CreateHelpCenterTables < ActiveRecord::Migration[8.1]
  def change
    create_table :support_requests do |t|
      t.string :kind, null: false, default: 'inquiry'
      t.string :category, null: false
      t.string :audience, null: false
      t.string :email, null: false
      t.text :body, null: false
      t.string :status, null: false, default: 'pending'
      t.text :staff_note
      t.bigint :member_id
      t.bigint :admin_user_id
      t.timestamps
    end
    add_index :support_requests, [:status, :created_at]
    add_index :support_requests, [:kind, :created_at]
    create_table :help_events do |t|
      t.string :kind, null: false
      t.string :query, limit: 100
      t.string :article_id
      t.string :audience
      t.string :category
      t.integer :result_count
      t.string :visitor_key, limit: 64, null: false
      t.date :recorded_on, null: false
      t.timestamps
    end
    add_index :help_events, :created_at
    add_index :help_events, [:visitor_key, :article_id, :recorded_on], unique: true, where: "kind IN ('helpful', 'unhelpful')", name: 'help_daily_feedback_unique'
  end
end
