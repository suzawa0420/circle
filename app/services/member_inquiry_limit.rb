# Counts first member submissions, not empty threads, replies or moderation releases.
# Call ensure_available! while holding the member row lock (Conversation#send_message!).
class MemberInquiryLimit
  DAILY_LIMIT = 5
  TIME_ZONE = 'Asia/Tokyo'
  MESSAGE = '本日の新しいサークルへのお問い合わせは5件に達しました。日本時間の午前0時以降にお試しください。すでに問い合わせたサークルとは引き続きやり取りできます。'.freeze

  def initialize(member, now: Time.current)
    @member = member
    @day = now.in_time_zone(TIME_ZONE).beginning_of_day
  end

  def used
    # Include held, rejected and soft-deleted submissions: moderation/deletion
    # must not refund quota. Group by circle so repeated messages count once.
    first_submissions = ChatMessage.joins(:conversation)
      .where(conversations: { member_id: @member.id, source_user_id: nil }, sender_role: 'member')
      .group('conversations.user_id')
      .having('MIN(chat_messages.created_at) >= ? AND MIN(chat_messages.created_at) < ?', @day, @day + 1.day)
      .select('conversations.user_id')
    Conversation.from("(#{first_submissions.to_sql}) daily_inquiries").count
  end

  def remaining
    [DAILY_LIMIT - used, 0].max
  end

  def ensure_available!(conversation)
    return if conversation.chat_messages.where(sender_role: 'member').exists?
    raise Conversation::NotAllowed, MESSAGE if remaining.zero?
  end
end
