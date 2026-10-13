class AddPublicCircleSortIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # Keep the policy literal and frozen, just like the visibility/count index.
  # Ordered keyword scans must not re-evaluate profile HTML on every candidate.
  PREDICATE = <<~SQL.squish.freeze
    publication_status = 'published' AND moderation_status = 'clear'
    AND (ng_account IS NULL OR ng_account = 'OK')
    AND (REGEXP_REPLACE(COALESCE(name, ''), '<[^>]*>', '', 'g') ~ '[ぁ-んァ-ヶ]'
    OR REGEXP_REPLACE(COALESCE(appeal, ''), '<[^>]*>', '', 'g') ~ '[ぁ-んァ-ヶ]')
  SQL
  INDEXES = {
    'index_users_public_on_switch_last_post' => :last_post,
    'index_users_public_on_switch_created_at' => :created_at
  }.freeze

  def up
    with_timeouts do
      # Preflight both names. A partial or invalid concurrent build needs
      # inspection; never silently accept or delete an existing index.
      if INDEXES.keys.any? { |name| index_name_exists?(:users, name) }
        raise 'Public sort index already exists; inspect validity and definition before retrying'
      end
      INDEXES.each do |name, column|
        add_index :users, [:switch, column], order: { column => :desc },
          where: PREDICATE, name: name, algorithm: :concurrently
      end
    end
  end

  def down
    with_timeouts do
      INDEXES.keys.reverse_each do |name|
        remove_index :users, name: name, algorithm: :concurrently
      end
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
