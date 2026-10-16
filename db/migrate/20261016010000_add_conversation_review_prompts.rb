class AddConversationReviewPrompts < ActiveRecord::Migration[8.1]
  def up
    %w[member owner].each do |role|
      add_column :conversations, "#{role}_review_prompt_after", :datetime
      add_column :conversations, "#{role}_review_prompt_dismissed", :boolean, default: false, null: false
    end
    # Preserve already published/closed conversations. Extend only open windows.
    execute <<~SQL
      UPDATE conversations
      SET review_deadline = accepted_at + INTERVAL '30 days'
      WHERE source_user_id IS NULL AND reviews_published_at IS NULL
        AND review_deadline > CURRENT_TIMESTAMP
        AND review_deadline < accepted_at + INTERVAL '30 days'
    SQL
  end

  def down
    %w[member owner].each do |role|
      remove_column :conversations, "#{role}_review_prompt_after"
      remove_column :conversations, "#{role}_review_prompt_dismissed"
    end
    # Do not shorten deadlines that have already been presented to users.
  end
end
