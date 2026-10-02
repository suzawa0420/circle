class AddEmailVerificationToAdminUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :admin_users, :email_verified_at, :datetime
    add_column :admin_users, :verification_sent_at, :datetime
  end
end
