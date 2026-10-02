class ChatMessage < ApplicationRecord
  belongs_to :conversation
  has_many :chat_reports, dependent: :nullify
  validates :sender_role, inclusion: { in: Conversation::ROLES }
  validates :body, presence: true, length: { maximum: 2000 }
end
