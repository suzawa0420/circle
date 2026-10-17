class ConversationReplyReport < ApplicationRecord
  belongs_to :conversation
  belongs_to :chat_message
  validates :reporter_role, inclusion: { in: Conversation::ROLES }, uniqueness: { scope: :conversation_id }
  validate :message_belongs_to_reporter

  # Compare delivery order, so a moderated message only counts once released.
  scope :active, -> {
    joins(:conversation, :chat_message).merge(ChatMessage.deliverable)
      .where(conversations: { source_user_id: nil, member_blocked: false, owner_blocked: false })
      .where(<<~SQL.squish)
        NOT EXISTS (
          SELECT 1 FROM chat_messages replies
          WHERE replies.conversation_id = conversation_reply_reports.conversation_id
            AND replies.sender_role = CASE conversation_reply_reports.reporter_role WHEN 'member' THEN 'owner' ELSE 'member' END
            AND replies.moderation_status IN ('delivered', 'approved')
            AND (COALESCE(replies.released_at, replies.created_at), replies.id) >
                (COALESCE(chat_messages.released_at, chat_messages.created_at), chat_messages.id)
        )
      SQL
  }

  private

  def message_belongs_to_reporter
    return if chat_message && chat_message.conversation_id == conversation_id && chat_message.sender_role == reporter_role
    errors.add(:chat_message, 'は報告者がこの会話に送ったメッセージを指定してください。')
  end
end
