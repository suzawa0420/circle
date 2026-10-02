class TransferLegacyWebmasterLogin < ActiveRecord::Migration[8.1]
  def up
    # Keep credentials inside the database: never select them into Ruby or logs.
    return if connection.select_value('SELECT EXISTS (SELECT 1 FROM webmasters WHERE id = 1)')
    unless connection.select_value("SELECT EXISTS (SELECT 1 FROM admin_users WHERE id = 1 AND email <> '' AND encrypted_password <> '')")
      raise '主催者ID 1のログイン情報がありません。ウェブマスターを設定してから再実行してください。'
    end
    execute <<~SQL
      INSERT INTO webmasters (id, email, encrypted_password, failed_attempts, created_at, updated_at)
      SELECT 1, email, encrypted_password, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM admin_users WHERE id = 1
      ON CONFLICT (id) DO NOTHING
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'ウェブマスターのログイン情報は削除しません。'
  end
end
