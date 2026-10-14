class PlaceInformationReport < ApplicationRecord
  KINDS = { 'closed' => '閉鎖・利用停止', 'hours' => '利用時間・定休日', 'price' => '利用料金',
            'address' => '住所・アクセス・連絡先', 'facility' => '設備・対応種目', 'other' => 'その他の情報' }.freeze
  STATUSES = { 'pending' => '未対応', 'in_progress' => '確認中', 'resolved' => '対応済み', 'dismissed' => '見送り' }.freeze

  belongs_to :place, optional: true
  belongs_to :reviewed_by, class_name: 'Webmaster', optional: true
  validates :place, presence: true, on: :create
  validates :kind, inclusion: { in: KINDS.keys }
  validates :status, inclusion: { in: STATUSES.keys }
  validates :body, length: { minimum: 10, maximum: 2000 }
  validates :place_name, :submission_key, presence: true
  validates :reference_url, length: { maximum: 2048 }
  validates :staff_note, length: { maximum: 4000 }
  validate :japanese_description
  validate :http_reference_url
  before_validation :normalize_submission

  private

  def normalize_submission
    self.body = body.to_s.strip
    self.reference_url = reference_url.to_s.strip
    return unless new_record? && place

    self.place_name = place.name
    self.submission_key = Digest::SHA256.hexdigest([place.id, kind, body, Date.current.iso8601].join("\n"))
  end

  def japanese_description
    unless body.to_s.match?(/\p{Han}/) && body.to_s.match?(/[ぁ-ゖ]/)
      errors.add(:body, 'は漢字とひらがなを両方含む日本語で入力してください')
    end
  end

  def http_reference_url
    return if reference_url.blank?

    uri = URI.parse(reference_url)
    unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?
      errors.add(:reference_url, 'はhttpまたはhttpsのURLを入力してください')
    end
  rescue URI::InvalidURIError
    errors.add(:reference_url, 'は正しいURLを入力してください')
  end
end
