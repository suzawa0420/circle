class ConversationReview < ApplicationRecord
  belongs_to :conversation
  has_one :review, dependent: :destroy
  has_many :chat_reports, dependent: :nullify
  validates :author_role, inclusion: { in: Conversation::ROLES }, uniqueness: { scope: :conversation_id }
  validates :score, inclusion: { in: [0, 1] }
  validates :comment, length: { minimum: 6, maximum: 2000 }, format: { without: Review::NGWORD_REGEX }
  validates :comment, format: { without: %r{https?://|www\.}i }
  scope :publicly_visible, -> { where.not(published_at: nil).where(deleted_at: nil) }
end
