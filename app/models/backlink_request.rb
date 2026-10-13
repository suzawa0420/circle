require 'uri'

class BacklinkRequest < ApplicationRecord
  POINTS = 10
  STATUSES = { 'pending' => '確認中', 'approved' => '付与済み', 'rejected' => '差し戻し', 'revoked' => '付与取り消し' }.freeze
  belongs_to :user
  belongs_to :reviewed_by, class_name: 'Webmaster', optional: true
  validates :user_id, uniqueness: true
  validates :status, inclusion: { in: STATUSES.keys }
  validates :placement_url, presence: true, length: { maximum: 2048 }
  validates :review_note, length: { maximum: 2000 }
  validates :review_note, presence: true, if: -> { status.in?(%w[rejected revoked]) }
  validates :submitted_at, presence: true
  validate :public_web_url

  def self.submit!(circle, url)
    circle.with_lock do
      request = find_or_initialize_by(user: circle)
      return request unless request.new_record? || request.status == 'rejected'
      request.update!(placement_url: url.to_s.strip, status: 'pending', submitted_at: Time.current,
                      review_note: nil, reviewed_by: nil)
      yield request if block_given?
      request
    end
  end

  def review!(decision, reviewer, note)
    # Serialize decisions with submissions and score refreshes for this circle.
    user.with_lock do
      reload
      allowed = { 'approve' => ['pending', 'approved'], 'reject' => ['pending', 'rejected'], 'revoke' => ['approved', 'revoked'] }[decision]
      return false unless allowed && status == allowed.first
      attrs = { status: allowed.last, reviewed_by: reviewer, review_note: note.to_s.strip }
      attrs[:approved_at] = Time.current if decision == 'approve'
      attrs[:revoked_at] = Time.current if decision == 'revoke'
      update!(attrs)
      CircleScoreUpdater.new.refresh(user)
      user.save!
    end
    true
  end

  private

  def public_web_url
    uri = URI.parse(placement_url.to_s)
    valid = uri.is_a?(URI::HTTP) && uri.host.present? && uri.host.include?('.') && uri.userinfo.nil?
    errors.add(:placement_url, 'は公開されている掲載ページの http:// または https:// URLを入力してください') unless valid
  rescue URI::InvalidURIError
    errors.add(:placement_url, 'の形式が正しくありません')
  end
end
