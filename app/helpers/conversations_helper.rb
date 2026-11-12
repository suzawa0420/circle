module ConversationsHelper
  # Display only; sending always recalculates under the account row lock.
  def remaining_member_inquiries
    @remaining_member_inquiries ||= MemberInquiryLimit.new(current_member).remaining
  end

  def report_message_options
    @messages.reject { |message| message.automatic? || message.sender_role == @role }.map do |message|
      body = message.deleted_at ? '削除されたメッセージ' : (message.body.presence || '写真')
      ["#{message.created_at.strftime('%Y/%m/%d %H:%M')} #{truncate(body, length: 60)}", message.id]
    end
  end

  def report_review_available?
    return @report_review_available if defined?(@report_review_available)

    @report_review_available = Conversation::ROLES.include?(@role) && !@conversation.practice_match? &&
      @conversation.review_writable?(@role) &&
      @conversation.conversation_reviews.none? do |review|
        review.author_role == @role && (review.deleted_at || review.published_at)
      end
  end
end
