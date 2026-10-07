class ChatMessage < ApplicationRecord
  mount_uploader :image, ChatImageUploader
  belongs_to :conversation
  has_many :chat_reports, dependent: :nullify
  validates :sender_role, inclusion: { in: Conversation::ROLES + ['system'] }
  validates :body, length: { maximum: 2000 }
  validates :body, presence: true, unless: :image?

  def preview_text
    image? ? ['写真', body.presence].compact.join('：') : body
  end

  def automatic?
    sender_role == 'system'
  end

  def sender_label
    automatic? ? '自動案内' : (sender_role == 'owner' ? '主催者' : '参加者')
  end
end
