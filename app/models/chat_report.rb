class ChatReport < ApplicationRecord
  belongs_to :conversation
  belongs_to :chat_message, optional: true
  belongs_to :conversation_review, optional: true
  validates :reporter_role, inclusion: { in: Conversation::ROLES }
  validates :reason, length: { minimum: 6, maximum: 2000 }
  STATUSES = { 'pending' => '未対応', 'in_progress' => '確認中', 'resolved' => '対応済み' }.freeze
  validates :status, inclusion: { in: STATUSES.keys }
  validates :operational_memo, length: { maximum: 4000 }
  before_save do
    self.resolved_at = status == 'resolved' ? (resolved_at || Time.current) : nil
  end
  validate :same_conversation

  private
  def same_conversation
    [chat_message, conversation_review].compact.each do |target|
      errors.add(:base, '対象の会話が一致しません。') if target.conversation_id != conversation_id
    end
  end
end
