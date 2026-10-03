class ChatMessage < ApplicationRecord
  belongs_to :conversation
  has_many :chat_reports, dependent: :nullify
  validates :sender_role, inclusion: { in: Conversation::ROLES + ['system'] }
  validates :body, presence: true, length: { maximum: 2000 }

  def automatic?
    sender_role == 'system'
  end

  def sender_label
    automatic? ? '自動案内' : (sender_role == 'owner' ? '主催者' : '参加者')
  end
end
