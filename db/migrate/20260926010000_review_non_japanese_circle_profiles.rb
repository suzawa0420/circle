class ReviewNonJapaneseCircleProfiles < ActiveRecord::Migration[8.1]
  def up
    # Existing published circles were screened under the old two-link rule.
    # Match the model's check of owner-written name and introduction so they
    # leave public listings immediately and the sitemap on its next refresh.
    execute <<~SQL
      UPDATE users
      SET moderation_status = 'review'
      WHERE publication_status = 'published'
        AND moderation_status = 'clear'
        AND (COALESCE(name, '') || ' ' ||
             REGEXP_REPLACE(COALESCE(appeal, ''), '<[^>]*>', '', 'g')) !~ '[ぁ-んァ-ヶ一-龠々]'
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Review decisions cannot be distinguished from later moderation"
  end
end
