class AddAlternateCircleListingIndexes < ActiveRecord::Migration[6.0]
  disable_ddl_transaction!

  INDEXES = {
    'index_users_on_switch_popularity_and_last_post' => {
      columns: %w[switch cb_point last_post], orders: { 'cb_point' => :desc, 'last_post' => :desc }
    },
    'index_users_on_switch_and_created_at_desc' => {
      columns: %w[switch created_at], orders: { 'created_at' => :desc }
    }
  }.freeze

  def up
    with_timeouts do
      INDEXES.each do |name, definition|
        if index_name_exists?(:users, name)
          valid = select_value("SELECT indisvalid FROM pg_index WHERE indexrelid = #{connection.quote(name)}::regclass")
          existing = connection.indexes(:users).find { |index| index.name == name }
          unless valid == true && existing && existing.columns == definition[:columns] &&
              existing.orders == definition[:orders] && existing.where.nil? && !existing.unique && existing.using == :btree
            raise 'Listing index exists with an invalid or unexpected definition; inspect before retrying'
          end
        else
          add_index :users, definition[:columns], order: definition[:orders],
            name: name, algorithm: :concurrently
        end
      end
    end
  end

  def down
    with_timeouts do
      INDEXES.keys.reverse_each do |name|
        remove_index :users, name: name, algorithm: :concurrently if index_name_exists?(:users, name)
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
