class AddCreationKeyToSchedules < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  INDEX_NAME = 'index_schedules_on_user_and_creation_key'

  def up
    with_lock_timeout do
      add_column :schedules, :creation_key, :uuid unless column_exists?(:schedules, :creation_key)
      if index_name_exists?(:schedules, INDEX_NAME)
        valid = select_value("SELECT indisvalid FROM pg_index WHERE indexrelid = #{connection.quote(INDEX_NAME)}::regclass")
        raise 'Schedule creation key index is invalid; inspect before retrying' unless valid == true
      else
        add_index :schedules, [:user_id, :creation_key], unique: true,
          where: 'creation_key IS NOT NULL', name: INDEX_NAME, algorithm: :concurrently
      end
    end
  end

  def down
    with_lock_timeout do
      remove_index :schedules, name: INDEX_NAME, algorithm: :concurrently
      remove_column :schedules, :creation_key
    end
  end

  private

  def with_lock_timeout
    previous = select_value('SHOW lock_timeout')
    execute "SET lock_timeout = '5s'"
    yield
  ensure
    execute "SET lock_timeout = #{connection.quote(previous)}" if previous
  end
end
