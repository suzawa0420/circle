# == Schema Information
#
# Table name: columns
#
#  id          :bigint           not null, primary key
#  description :text
#  image       :string
#  text        :text
#  title       :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class Column < ApplicationRecord
  AUDIENCES = { 'all' => '参加者・主催者', 'participant' => '参加者向け', 'organizer' => '主催者向け' }.freeze
  belongs_to :event, optional: true
  has_many :column_products, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :column
  accepts_nested_attributes_for :column_products, allow_destroy: true, limit: 12,
    reject_if: ->(attributes) { attributes.slice('name', 'description', 'amazon_url', 'mercari_url').values.all?(&:blank?) }

  scope :published, -> { where(publication_status: 'published') }
  scope :for_participant_interests, ->(event_ids) {
    published.where(event_id: event_ids).where(audience: %w[all participant]).order(updated_at: :desc, id: :desc)
  }
  scope :for_readers, ->(event_id, audience) {
    published.where(event_id: [nil, event_id]).where(audience: ['all', audience]).order(updated_at: :desc, id: :desc)
  }

  validates :title, presence: true, length: { maximum: 200 }
  validates :text, presence: true, if: :published?
  validates :publication_status, inclusion: { in: %w[draft published] }
  validates :audience, inclusion: { in: AUDIENCES.keys }
  validate :product_count_within_limit
  validate :readable_published_body
  validate :inline_products_exist
  before_save :set_publication_date

  mount_uploader :image, ColumnImageUploader

  def published?
    publication_status == 'published'
  end

  def affiliate?
    self[:affiliate] || amazon_links?
  end

  def amazon_links?
    column_products.reject(&:marked_for_destruction?).any? { |product| product.amazon_url.present? } ||
      text.to_s.match?(/amazon\.co\.jp|amzn\.to/i)
  end

  private

  def set_publication_date
    self.published_at ||= Time.current if published?
  end

  def product_count_within_limit
    errors.add(:base, '紹介商品は12件以内にしてください。') if column_products.reject(&:marked_for_destruction?).size > 12
  end

  def readable_published_body
    return unless published? && text.present?
    errors.add(:text, 'を入力してください。') if ActionView::Base.full_sanitizer.sanitize(text).squish.blank?
  end

  def inline_products_exist
    return unless published?
    count = column_products.reject(&:marked_for_destruction?).size
    if text.to_s.scan(/\[商品:([1-9]\d*)\]/).flatten.any? { |number| number.to_i > count }
      errors.add(:text, 'の商品カード番号に対応する商品がありません。表示順と本文の番号を確認してください。')
    end
  end
end
