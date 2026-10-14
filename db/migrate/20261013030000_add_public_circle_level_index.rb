class AddPublicCircleLevelIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  PREDICATE = <<~SQL.squish.freeze
    publication_status = 'published' AND moderation_status = 'clear'
    AND (ng_account IS NULL OR ng_account = 'OK')
    AND (REGEXP_REPLACE(COALESCE(name, ''), '<[^>]*>', '', 'g') ~ '[ぁ-んァ-ヶ]'
    OR REGEXP_REPLACE(COALESCE(appeal, ''), '<[^>]*>', '', 'g') ~ '[ぁ-んァ-ヶ]')
  SQL
  INDEX_NAME = 'index_users_public_on_circle_level_order'.freeze
  COLUMNS = 'switch ASC, LEAST(100, GREATEST(0, FLOOR(ROUND(cb_point::numeric, 1)))) DESC, last_post DESC, id DESC'.freeze

  def up
    with_timeouts do
      if index_name_exists?(:users, INDEX_NAME)
        raise 'Public level index already exists; inspect validity and definition before retrying'
      end
      add_index :users, COLUMNS, where: PREDICATE, name: INDEX_NAME, algorithm: :concurrently
    end
  end

  def down
    with_timeouts { remove_index :users, name: INDEX_NAME, algorithm: :concurrently }
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
