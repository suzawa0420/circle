module ConversationsHelper
  def participant_report_review_available?
    return @participant_report_review_available if defined?(@participant_report_review_available)

    @participant_report_review_available = @role == 'owner' && !@conversation.practice_match? &&
      @conversation.review_writable?(@role) &&
      @conversation.conversation_reviews.none? do |review|
        review.author_role == @role && (review.deleted_at || review.published_at)
      end
  end
end
