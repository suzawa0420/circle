class ChatMessageReaction < ApplicationRecord
  OPTIONS = {
    'understood' => ['👍', '了解です'],
    'thanks' => ['🙏', 'ありがとうございます'],
    'checked' => ['✅', '確認しました'],
    'like' => ['❤️', 'いいですね'],
    'excited' => ['😊', '楽しみです']
  }.transform_values(&:freeze).freeze

  belongs_to :chat_message
  belongs_to :member, optional: true
  belongs_to :admin_user, optional: true
  validates :key, inclusion: { in: OPTIONS.keys }
  validate do
    errors.add(:base, 'リアクションの投稿者を1人指定してください。') if member_id.present? == admin_user_id.present?
  end

  def self.account_attributes(account)
    ConversationNote.account_attributes(account)
  end

  def by_account?(account)
    self.class.account_attributes(account).all? { |attribute, value| self[attribute] == value }
  end
end
