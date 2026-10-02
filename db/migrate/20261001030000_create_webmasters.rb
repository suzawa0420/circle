class CreateWebmasters < ActiveRecord::Migration[8.1]
  def change
    create_table :webmasters do |t|
      t.string :email, null: false, default: ''
      t.string :encrypted_password, null: false, default: ''
      t.integer :failed_attempts, null: false, default: 0
      t.datetime :locked_at
      t.timestamps
    end
    add_index :webmasters, :email, unique: true
    add_check_constraint :webmasters, 'id = 1', name: 'webmasters_single_account'
  end
end
