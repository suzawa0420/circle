# Database deadlines survive restarts. Run once a minute with cron or a local worker.
class ChatMaintenance
  class DeliveryFailed < StandardError; end

  def self.run
    HelpEvent.where('created_at < ?', 90.days.ago).delete_all
    Conversation.where(reviews_published_at: nil).where('review_deadline <= ?', Time.current).find_each(&:publish_reviews!)
    failures = 0
    Conversation::ROLES.each do |role|
      Conversation.where("#{role}_notification_due_at <= ?", Time.current).find_each do |conversation|
        begin
          deliver_pending(conversation, role)
        rescue StandardError => error
          # Never put message bodies, addresses or mail-provider error details in logs.
          Rails.logger.error("[ChatMaintenance] delivery_failed conversation_id=#{conversation.id} role=#{role} error_class=#{error.class.name}")
          failures += 1
        end
      end
    end
    raise DeliveryFailed, 'One or more notifications failed; pending notifications will be retried.' if failures.positive?
  end

  def self.deliver_pending(conversation, role)
    conversation.with_lock do
      due = conversation["#{role}_notification_due_at"]
      return unless due && due <= Time.current
      incoming = role == 'member' ? 'owner' : 'member'
      unread = conversation.chat_messages.where(sender_role: incoming).where('id > ?', conversation["#{role}_read_message_id"]).exists?
      if unread && !conversation.blocked?
        ChatMailer.new_messages(conversation, role).deliver_now
        conversation["#{role}_notified_at"] = Time.current
      end
      conversation["#{role}_notification_due_at"] = nil
      conversation.save!
    end
  end
end
