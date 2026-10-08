class AddPublicVisibilityIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  INDEX_NAME = 'index_users_on_public_visibility'.freeze
  # Freeze the exact publication policy at this migration's version. Do not
  # reference the live User model from a historical migration.
  PREDICATE = <<~SQL.squish.freeze
    publication_status = 'published' AND moderation_status = 'clear'
    AND (ng_account IS NULL OR ng_account = 'OK')
    AND (REGEXP_REPLACE(COALESCE(name, ''), '<[^>]*>', '', 'g') ~ '[ぁ-んァ-ヶ]'
    OR REGEXP_REPLACE(COALESCE(appeal, ''), '<[^>]*>', '', 'g') ~ '[ぁ-んァ-ヶ]')
  SQL

  def up
    with_timeouts do
      # A failed concurrent build can leave an invalid index. Fail explicitly
      # instead of silently accepting it or dropping an existing index.
      if index_name_exists?(:users, INDEX_NAME)
        raise 'Public visibility index already exists; inspect validity and definition before retrying'
      end
      add_index :users, [:id, :admin_user_id], where: PREDICATE,
        name: INDEX_NAME, algorithm: :concurrently
    end
  end

  def down
    with_timeouts do
      remove_index :users, name: INDEX_NAME, algorithm: :concurrently
    end
  end

  private

  def with_timeouts
    previous_lock = select_value('SHOW lock_timeout')
    previous_statement = select_value('SHOW statement_timeout')
    execute "SET lock_timeout = '5s'"
    execute "SET statement_timeout = '10min'"
    yield
  ensure
    execute "SET statement_timeout = #{connection.quote(previous_statement)}" if previous_statement
    execute "SET lock_timeout = #{connection.quote(previous_lock)}" if previous_lock
  end
end
