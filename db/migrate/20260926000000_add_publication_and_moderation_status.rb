class AddPublicationAndModerationStatus < ActiveRecord::Migration[6.0]
  def up
    add_column :users, :publication_status, :string, default: "draft", null: false
    add_column :users, :moderation_status, :string, default: "clear", null: false
    add_column :blogs, :moderation_status, :string, default: "clear", null: false
    add_index :users, [:publication_status, :moderation_status]
    add_index :blogs, :moderation_status

    # Existing circles are evaluated once during rollout. Owners can complete
    # the missing fields later; subsequent saves use the same Ruby rules.
    execute <<~SQL
      UPDATE users SET publication_status = 'published'
      WHERE NULLIF(BTRIM(name), '') IS NOT NULL
        AND event_id IS NOT NULL AND prefecture_id IS NOT NULL
        AND NULLIF(BTRIM(switch), '') IS NOT NULL
        AND NULLIF(BTRIM(area), '') IS NOT NULL
        AND NULLIF(BTRIM(schedule), '') IS NOT NULL
        AND LENGTH(REGEXP_REPLACE(REGEXP_REPLACE(COALESCE(appeal, ''), '<[^>]*>', '', 'g'), '[[:space:]]', '', 'g')) >= 100
    SQL
    execute <<~SQL
      WITH profiles AS (
        SELECT id, LOWER(REGEXP_REPLACE(COALESCE(appeal, ''), '<[^>]*>', '', 'g')) AS body FROM users
      )
      UPDATE users SET moderation_status = 'review' FROM profiles
      WHERE users.id = profiles.id AND profiles.body !~ '[ぁ-んァ-ヶ一-龠々]'
        AND GREATEST(
          (LENGTH(profiles.body) - LENGTH(REPLACE(profiles.body, 'http', ''))) / 4,
          (LENGTH(profiles.body) - LENGTH(REPLACE(profiles.body, 'www.', ''))) / 4
        ) >= 2
    SQL
    execute <<~SQL
      WITH posts AS (
        SELECT id, LOWER(REGEXP_REPLACE(COALESCE(content, ''), '<[^>]*>', '', 'g')) AS body FROM blogs
      )
      UPDATE blogs SET moderation_status = 'review' FROM posts
      WHERE blogs.id = posts.id AND posts.body !~ '[ぁ-んァ-ヶ一-龠々]'
        AND GREATEST(
          (LENGTH(posts.body) - LENGTH(REPLACE(posts.body, 'http', ''))) / 4,
          (LENGTH(posts.body) - LENGTH(REPLACE(posts.body, 'www.', ''))) / 4
        ) >= 2
    SQL
  end

  def down
    remove_index :blogs, :moderation_status
    remove_index :users, [:publication_status, :moderation_status]
    remove_column :blogs, :moderation_status
    remove_column :users, :moderation_status
    remove_column :users, :publication_status
  end
end
