class SetReviewPublicationWaitToTwoWeeks < ActiveRecord::Migration[8.1]
  def up
    add_column :conversations, :first_review_submitted_at, :datetime
    # Preserve public reviews. Pending reviews publish 14 days after the first post.
    execute <<~SQL
      UPDATE conversations
      SET first_review_submitted_at = first_reviews.submitted_at,
          review_deadline = CASE WHEN conversations.reviews_published_at IS NULL
            THEN first_reviews.submitted_at + INTERVAL '14 days'
            ELSE conversations.review_deadline END
      FROM (
        SELECT conversation_id, MIN(created_at) AS submitted_at
        FROM conversation_reviews GROUP BY conversation_id
      ) first_reviews
      WHERE conversations.id = first_reviews.conversation_id
        AND conversations.source_user_id IS NULL
        AND conversations.accepted_at IS NOT NULL
    SQL
  end

  def down
    remove_column :conversations, :first_review_submitted_at
    # Do not postpone publication dates already shown to users.
  end
end
