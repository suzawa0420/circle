class ChatMessage < ApplicationRecord
  mount_uploader :image, ChatImageUploader
  belongs_to :conversation
  has_many :chat_reports, dependent: :nullify
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

  def receipt_text(conversation)
    return moderation_status == 'held' ? '運営確認中' : '未配信' unless delivered?
    conversation.message_read?(self) ? '既読' : '未読'
  end

  def moderate!(decision)
    raise ArgumentError unless decision.in?(%w[approve spam])
    conversation.with_lock do
      with_lock do
        return false unless moderation_status == 'held'
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
    content = image? ? ['写真', body.presence].compact.join('：') : body
    delivered? ? content : "［#{STATUSES.fetch(moderation_status)}］#{content}"
  end

  def automatic?
    sender_role == 'system'
  end

  def sender_label
    automatic? ? '自動案内' : (sender_role == 'owner' ? '主催者' : '参加者')
  end
end
