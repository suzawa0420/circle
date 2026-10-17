class NoShowReport < ApplicationRecord
  belongs_to :conversation
  STATUSES = { 'pending' => '未確認の申告', 'confirmed' => '運営確認済み', 'dismissed' => '集計対象外' }.freeze
  scope :counted, -> { where(status: %w[pending confirmed]) }
  validates :status, inclusion: { in: STATUSES.keys }
  validates :scheduled_at, presence: true, uniqueness: { scope: :conversation_id }
  validates :participation_confirmed, :no_advance_notice, inclusion: { in: [true] }
  validates :confirmation_details, :details, length: { maximum: 2000 }
  before_validation do
    self.confirmation_details ||= ''
    self.details ||= ''
  end
  validates :member_response, length: { minimum: 6, maximum: 2000 }, allow_nil: true
  validates :operational_memo, length: { maximum: 4000 }
  validate :eligible_event, on: :create

  def self.profile_viewable_by?(owner, webmaster: false)
    webmaster || (owner && owner.email_verified? && !owner.suspended? && owner.users.exists?)
  end

  private

  def eligible_event
    errors.add(:base, '参加者との受付済みの会話から報告してください。') if !conversation || conversation.practice_match? || !conversation.accepted_at
    errors.add(:scheduled_at, 'は過去の参加予定日時を入力してください。') if scheduled_at && scheduled_at > Time.current
    errors.add(:scheduled_at, 'はお問い合わせ以降の日時を入力してください。') if scheduled_at && conversation && scheduled_at < conversation.created_at
  end
end
