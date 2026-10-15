# Public recruitment pages reviewed on 2026-10-15. Never classify all keyword
# matches: a profile may mention another sport without actually offering it.
class ClassifyReviewedSports < ActiveRecord::Migration[8.1]
  def up
    execute "SET LOCAL lock_timeout = '5s'"
    reviewed_rows.each do |id, previous, target, category, name_fragment, secondary|
      next unless select_value("SELECT 1 FROM events WHERE id = #{Integer(target)}")
      condition = sanitize(["id = ? AND event_id = ? AND name LIKE ?", id, previous, "%#{name_fragment}%"])
      if secondary
        execute <<~SQL
          UPDATE users SET secondary_event_ids = array_append(secondary_event_ids, #{Integer(target)})
          WHERE #{condition} AND NOT secondary_event_ids @> ARRAY[#{Integer(target)}]::integer[]
        SQL
      else
        execute <<~SQL
          UPDATE users SET event_id = #{Integer(target)}, category_id = #{Integer(category)},
            secondary_event_ids = array_remove(secondary_event_ids, #{Integer(target)})
          WHERE #{condition}
        SQL
      end
    end
    ids = reviewed_rows.flat_map { |row| [row[1], row[2]] }.uniq.map { |id| Integer(id) }.join(',')
    execute "UPDATE events SET users_count = (SELECT COUNT(*) FROM users WHERE users.event_id = events.id) WHERE events.id IN (#{ids})"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Do not overwrite subsequent organizer classification edits'
  end

  private

  def reviewed_rows
    [
      [21302, 9, 59, 2, 'ソフトテニス', false],
      [26929, 9, 59, 2, 'ソフトテニス', false],
      [14807, 9, 60, 2, 'ピックルボール', false],
      [13737, 9, 60, 2, 'ピックルボール', false],
      [10942, 20, 61, 4, 'スキーサークル', false],
      [11833, 20, 61, 4, 'スキーサークル', true]
    ]
  end

  def sanitize(args)
    ActiveRecord::Base.send(:sanitize_sql_array, args)
  end
end
