class SupportRequest < ApplicationRecord
  KINDS = { 'inquiry' => 'FAQで解決しない問い合わせ', 'suggestion' => 'ご意見・改善提案', 'safety' => '迷惑行為・安全上の問題' }.freeze
  AUDIENCES = { 'member' => '参加者', 'owner' => '主催者', 'other' => 'その他・登録前' }.freeze
  STATUSES = { 'pending' => '未対応', 'in_progress' => '対応中', 'resolved' => '対応済み' }.freeze
  belongs_to :member, optional: true
  belongs_to :admin_user, optional: true
  validates :kind, inclusion: { in: KINDS.keys }
  validates :category, inclusion: { in: HelpCatalog::CATEGORIES.keys }
  validates :audience, inclusion: { in: AUDIENCES.keys }
  validates :status, inclusion: { in: STATUSES.keys }
  before_validation { self.email = email.to_s.strip }
  validates :email, presence: true, unless: -> { kind == 'suggestion' }
  validates :email, length: { maximum: 254 }, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :body, presence: true, length: { minimum: 10, maximum: 4000 }
  validates :staff_note, length: { maximum: 4000 }
end
