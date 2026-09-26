class ReviewCircleProfilesWithoutJapaneseKana < ActiveRecord::Migration[8.1]
  def up
    # Han characters alone can be Chinese. Recheck owner-written fields with
    # the same kana requirement used for newly saved circle profiles.
    execute <<~SQL
      UPDATE users
      SET moderation_status = 'review'
      WHERE publication_status = 'published'
        AND moderation_status = 'clear'
        AND (COALESCE(name, '') || ' ' ||
             REGEXP_REPLACE(COALESCE(appeal, ''), '<[^>]*>', '', 'g')) !~ '[ぁ-んァ-ヶ]'
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Review decisions cannot be distinguished from later moderation"
  end
end
