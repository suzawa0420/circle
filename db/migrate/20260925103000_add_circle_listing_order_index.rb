class AddCircleListingOrderIndex < ActiveRecord::Migration[6.0]
  disable_ddl_transaction!

  INDEX_NAME = 'index_users_on_switch_and_last_post_desc'.freeze

  def up
    with_timeouts do
      if index_name_exists?(:users, INDEX_NAME)
        valid = select_value(<<~SQL)
          SELECT i.indisvalid FROM pg_index i
          JOIN pg_class c ON c.oid = i.indexrelid
          WHERE c.oid = #{connection.quote(INDEX_NAME)}::regclass
        SQL
        raise 'Listing index exists but is invalid; inspect before retrying' unless valid == true
        existing = connection.indexes(:users).find { |index| index.name == INDEX_NAME }
        unless existing && existing.columns == %w[switch last_post] &&
            existing.orders == { 'last_post' => :desc } && existing.where.nil? && !existing.unique
          raise 'Listing index name has an unexpected definition; inspect before retrying'
        end
      else
        add_index :users, [:switch, :last_post],
          order: { switch: :asc, last_post: :desc },
          name: INDEX_NAME, algorithm: :concurrently
      end
    end
  end

  def down
    with_timeouts do
      remove_index :users, name: INDEX_NAME, algorithm: :concurrently if index_name_exists?(:users, INDEX_NAME)
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
