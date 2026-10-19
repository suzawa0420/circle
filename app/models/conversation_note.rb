class ConversationNote < ApplicationRecord
  belongs_to :conversation
  belongs_to :member, optional: true
  belongs_to :admin_user, optional: true
  validates :body, length: { maximum: 300 }
  validate :one_account

  def self.account_attributes(account)
    case account
    when Member then { member_id: account.id, admin_user_id: nil }
    when AdminUser then { member_id: nil, admin_user_id: account.id }
    else raise ArgumentError, 'A chat account is required'
    end
  end

  scope :for_account, ->(account) { where(account_attributes(account)) }

  private

  def one_account
    errors.add(:base, 'メモの所有者を1人指定してください。') if member_id.present? == admin_user_id.present?
  end
end
