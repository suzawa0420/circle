class AddDbKeywordLookupIndex < ActiveRecord::Migration[6.0]
  disable_ddl_transaction!
  INDEX_NAME = 'index_db_keywords_on_keyword_hash'.freeze

  def up
    with_timeouts do
      if index_name_exists?(:db_keywords, INDEX_NAME)
        valid = select_value("SELECT indisvalid FROM pg_index WHERE indexrelid = #{connection.quote(INDEX_NAME)}::regclass")
        index = connection.indexes(:db_keywords).find { |i| i.name == INDEX_NAME }
        unless valid == true && index && index.columns == ['keyword'] &&
            index.using == :hash && !index.unique && index.where.nil?
          raise 'Keyword index has an invalid or unexpected definition; inspect before retrying'
        end
      else
        # Lookups use equality only. Hash indexes do not impose B-tree's indexed
        # value size limit on the unrestricted user-entered keyword column.
        add_index :db_keywords, :keyword, using: :hash, name: INDEX_NAME, algorithm: :concurrently
      end
    end
  end

  def down
    with_timeouts do
      remove_index :db_keywords, name: INDEX_NAME, algorithm: :concurrently if index_name_exists?(:db_keywords, INDEX_NAME)
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
