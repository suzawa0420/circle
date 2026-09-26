class AddMatchLookupIndexes < ActiveRecord::Migration[6.0]
  disable_ddl_transaction!

  INDEXES = {
    'index_matches_on_recruit_and_updated_at' => %w[recruit updated_at],
    'index_matches_on_user_id_and_updated_at' => %w[user_id updated_at]
  }.freeze

  def up
    with_timeouts do
      INDEXES.each do |name, columns|
        if index_name_exists?(:matches, name)
          valid = select_value("SELECT indisvalid FROM pg_index WHERE indexrelid = #{connection.quote(name)}::regclass")
          index = connection.indexes(:matches).find { |candidate| candidate.name == name }
          unless valid == true && index && index.columns == columns &&
              index.using == :btree && !index.unique && index.where.nil?
            raise "Match index #{name} has an invalid or unexpected definition; inspect before retrying"
          end
        else
          add_index :matches, columns, name: name, algorithm: :concurrently
        end
      end
    end
  end

  def down
    with_timeouts do
      INDEXES.keys.reverse_each do |name|
        remove_index :matches, name: name, algorithm: :concurrently if index_name_exists?(:matches, name)
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
