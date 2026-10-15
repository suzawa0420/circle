class AddSportDiscovery < ActiveRecord::Migration[8.1]
  def up
    execute "SET LOCAL lock_timeout = '5s'"
    add_column :users, :secondary_event_ids, :integer, array: true, default: [], null: false
    add_column :users, :sport_details, :jsonb, default: {}, null: false
    [[59, 2, '0206', 'ソフトテニス', 'soft-tennis'],
     [60, 2, '0207', 'ピックルボール', 'pickleball'],
     [61, 4, '0403', 'スキー', 'ski']].each do |id, category, order, name, slug|
      execute sanitize_sql_array([<<~SQL, id, category, order, name, slug, "#{name}サークル"])
        INSERT INTO events (id, category_id, "order", name, ruby, txt, matching, place, openchat, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, 0, 0, '', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      SQL
    end
    execute "SELECT setval(pg_get_serial_sequence('events', 'id'), (SELECT MAX(id) FROM events))"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Keep registered sports and owner-entered details on application rollback'
  end

  private

  def sanitize_sql_array(args)
    ActiveRecord::Base.send(:sanitize_sql_array, args)
  end
end
