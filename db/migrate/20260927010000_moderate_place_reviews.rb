class ModeratePlaceReviews < ActiveRecord::Migration[8.1]
  def up
    add_column :place_reviews, :moderation_status, :string, default: "clear", null: false
    add_index :place_reviews, [:place_id, :moderation_status]

    backfill
  end

  def backfill
    execute <<~SQL
      CREATE TEMP TABLE affected_place_reviews (place_id bigint PRIMARY KEY) ON COMMIT DROP;

      INSERT INTO affected_place_reviews (place_id)
      SELECT DISTINCT place_id FROM place_reviews
      WHERE place_id IS NOT NULL
        AND (COALESCE(comment, '') !~ '[ぁ-んァ-ヶ]'
          OR comment ~* '(union[[:space:]]+select|select.{0,80}from|pg_sleep|benchmark|waitfor[[:space:]]+delay)');

      INSERT INTO affected_place_reviews (place_id) VALUES (1925) ON CONFLICT DO NOTHING;

      UPDATE place_reviews
      SET moderation_status = 'review'
      WHERE COALESCE(comment, '') !~ '[ぁ-んァ-ヶ]'
         OR comment ~* '(union[[:space:]]+select|select.{0,80}from|pg_sleep|benchmark|waitfor[[:space:]]+delay)';

      -- All 305 public comments on facility 1925 lacked Japanese kana;
      -- the sampled text was automated probe/garbage content.
      -- The cutoff prevents this one-time cleanup from deleting later submissions.
      DELETE FROM place_reviews
      WHERE place_id = 1925
        AND updated_at < TIMESTAMPTZ '2026-09-04 00:00:00+00'
        AND moderation_status = 'review'
        AND COALESCE(comment, '') !~ '[ぁ-んァ-ヶ]';

      UPDATE places
      SET average_facility = (SELECT AVG(facility) FROM place_reviews WHERE place_id = places.id AND moderation_status = 'clear'),
          average_reservation = (SELECT AVG(reservation) FROM place_reviews WHERE place_id = places.id AND moderation_status = 'clear'),
          average_price = (SELECT AVG(price) FROM place_reviews WHERE place_id = places.id AND moderation_status = 'clear'),
          average_access = (SELECT AVG(access) FROM place_reviews WHERE place_id = places.id AND moderation_status = 'clear'),
          average_score = (SELECT (AVG(facility) + AVG(reservation) + AVG(price) + AVG(access)) / 4.0
                           FROM place_reviews WHERE place_id = places.id AND moderation_status = 'clear'),
          updated_at = CURRENT_TIMESTAMP
      WHERE id IN (SELECT place_id FROM affected_place_reviews);
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Reviewed and removed comments cannot be reconstructed"
  end
end
