class AddCheckInStartedAtToSchedules < ActiveRecord::Migration[8.1]
  def change
    # Fail safely rather than waiting behind another query in production.
    execute "SET LOCAL lock_timeout = '3s'" if connection.adapter_name == 'PostgreSQL'
    add_column :schedules, :check_in_started_at, :datetime
  end
end
