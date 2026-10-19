class ChatMessage < ApplicationRecord
  mount_uploader :image, ChatImageUploader
  belongs_to :conversation
  has_many :chat_reports, dependent: :nullify
  has_many :conversation_reply_reports, dependent: :destroy
  validates :sender_role, inclusion: { in: Conversation::ROLES + ['system'] }
  validates :body, length: { maximum: 2000 }
  validates :body, presence: true, unless: :image?

  STATUSES = { 'delivered' => '配信済み', 'held' => '運営確認中', 'approved' => '配信許可済み', 'spam' => 'スパムと確認・未配信' }.freeze
  validates :moderation_status, inclusion: { in: STATUSES.keys }
  scope :deliverable, -> { where(moderation_status: %w[delivered approved]) }
  scope :visible_to, ->(role) { deliverable.or(where(sender_role: role)) }
  scope :delivery_order, -> { order(Arel.sql('COALESCE(released_at, created_at) DESC'), id: :desc) }
  scope :unread_by, ->(role, cursor) {
    deliverable.where(sender_role: role == 'owner' ? 'member' : 'owner')
      .where('(released_at IS NULL AND id > ?) OR (released_at IS NOT NULL AND recipient_read_at IS NULL)', cursor)
  }

  def delivered? = moderation_status.in?(%w[delivered approved])

  CHANGE_WINDOW = 12.hours

  def changeable_by?(role, now: Time.current)
    !automatic? && sender_role == role && deleted_at.nil? &&
      created_at.present? && created_at <= now && created_at + CHANGE_WINDOW > now
  end

  def deletion_notice
    "#{conversation.participant_name(sender_role)}さんがメッセージを削除しました。"
  end

  def revise!(role, body: nil, delete: false)
    conversation.with_lock do
      with_lock do
        raise Conversation::NotAllowed, '自分が送信した12時間以内のメッセージのみ編集・削除できます。' unless changeable_by?(role)
        conversation.ensure_active_sender!(role)
        if delete
          # Retain the record and moderation evidence; all displays hide its contents.
          update!(deleted_at: Time.current)
        else
          return false if self.body == body.to_s
          self.body = body.to_s
          self.edited_at = Time.current
          if sender_role == 'member'
            result = ChatSpamDetector.evaluate(conversation, self.body)
            self.spam_score, self.spam_reasons, self.spam_fingerprint = result.score, result.reasons, result.fingerprint
            if result.held? || !delivered?
              self.moderation_status = 'held'
              self.reviewed_at = nil
              self.released_at = nil
              self.recipient_read_at = nil
            end
          end
          save!
        end
        true
      end
    end
  end

  def receipt_text(conversation)
    return moderation_status == 'held' ? '運営確認中' : '未配信' unless delivered?
    conversation.message_read?(self) ? '既読' : '未読'
  end

  def moderate!(decision)
    raise ArgumentError unless decision.in?(%w[approve spam])
    conversation.with_lock do
      with_lock do
        return false unless moderation_status == 'held' && deleted_at.nil?
        update!(moderation_status: decision == 'approve' ? 'approved' : 'spam', reviewed_at: Time.current,
                released_at: decision == 'approve' ? Time.current : nil, recipient_read_at: nil)
        if decision == 'approve'
          recipient = sender_role == 'member' ? 'owner' : 'member'
          last_notified = conversation["#{recipient}_notified_at"]
          conversation.update!("#{recipient}_notification_due_at" => conversation["#{recipient}_notification_due_at"] || [5.minutes.from_now, last_notified && last_notified + 15.minutes].compact.max)
        else
          ChatSpamDetector.destinations(body).each { |destination| ChatSpamDestination.create_or_find_by!(destination: destination) if destination.length <= 2048 }
        end
        true
      end
    end
  end

  def preview_text
    return deletion_notice if deleted_at
    content = image? ? ['写真', body.presence].compact.join('：') : body
    content = "（編集済み）#{content}" if edited_at
    delivered? ? content : "［#{STATUSES.fetch(moderation_status)}］#{content}"
  end

  def automatic?
    sender_role == 'system'
  end

  def sender_label
    automatic? ? '自動案内' : (sender_role == 'owner' || conversation.practice_match? ? '主催者' : '参加者')
  end
end
