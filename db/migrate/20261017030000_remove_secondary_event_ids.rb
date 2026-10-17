# Release only after c2ca5047b (or a descendant) has been activated on BOTH
# production servers. The previous workers still reference this column.
class RemoveSecondaryEventIds < ActiveRecord::Migration[8.1]
  def up
    execute "SET LOCAL lock_timeout = '5s'"
    # PostgreSQL also removes the GIN index belonging to this column.
    remove_column :users, :secondary_event_ids, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Retired secondary sport assignments cannot be reconstructed'
  end
end
