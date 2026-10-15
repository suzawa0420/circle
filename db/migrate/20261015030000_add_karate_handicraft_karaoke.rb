class AddKarateHandicraftKaraoke < ActiveRecord::Migration[8.1]
  def up
    execute "SET LOCAL lock_timeout = '5s'"
    [[62, 3, '03105', '空手', 'karate'],
     [63, 12, '0904', '手芸・ハンドメイド', 'handicraft'],
     [64, 9, '1004', 'カラオケ', 'karaoke']].each do |id, category, order, name, slug|
      # Fail on an unexpected existing ID/slug instead of overwriting a category.
      if select_value(sanitize(['SELECT 1 FROM events WHERE id = ? OR ruby = ?', id, slug]))
        raise "Category ID or slug already exists: #{id}/#{slug}"
      end
      execute sanitize([<<~SQL, id, category, order, name, slug, "#{name}サークル"])
        INSERT INTO events (id, category_id, "order", name, ruby, txt, matching, place, openchat, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, 0, 0, '', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      SQL
    end
    execute "SELECT setval(pg_get_serial_sequence('events', 'id'), (SELECT MAX(id) FROM events))"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Keep categories referenced by organizer registrations'
  end

  private

  def sanitize(args)
    ActiveRecord::Base.send(:sanitize_sql_array, args)
  end
end
