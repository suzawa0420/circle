# == Schema Information
#
# Table name: blogs
#
#  id                 :bigint           not null, primary key
#  blog_image_name    :string
#  content            :text
#  image_01           :string
#  image_02           :string
#  image_03           :string
#  image_04           :string
#  impressions_count  :integer          default(0)
#  photo              :string
#  photo_content_type :string
#  photo_file_name    :string
#  photo_file_size    :string
#  photo_updated_at   :string
#  title              :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  user_id            :bigint
#
# Indexes
#
#  index_blogs_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class Blog < ApplicationRecord
  include PublicListingOrder
  include RemembersCircleActivity
  belongs_to :user
  before_validation :flag_suspicious_content

  scope :publicly_visible, -> { where(moderation_status: "clear", user_id: User.publicly_visible.select(:id)) }

  # Keep historical decisions and their publication status intact. Only skip
  # queue entries whose saved evidence consists entirely of the retired rule.
  scope :awaiting_moderation, -> {
    where(moderation_status: "review").where(<<~SQL.squish, '[{"code":"duplicate_content"}]', 'duplicate_content')
      NOT (
        moderation_checked_at IS NOT NULL
        AND moderation_reasons @> CAST(? AS jsonb)
        AND NOT EXISTS (
          SELECT 1 FROM jsonb_array_elements(blogs.moderation_reasons) AS reasons(reason)
          WHERE reasons.reason->>'code' IS DISTINCT FROM ?
        )
      )
    SQL
  }

  def publicly_visible?
    moderation_status == "clear" && user.publicly_visible?
  end

  def moderation_rule_reasons
    body = ActionView::Base.full_sanitizer.sanitize([title, content].join(" "))
    reasons = []
    reasons << 'foreign_links' if body !~ User::JAPANESE_TEXT && body.scan(User::LINK_TEXT).length >= 2
    reasons
  end

  private

  def reject_recent_duplicates
    return if user_id.blank?

    check_title = title.present? && (new_record? || will_save_change_to_title?)
    check_content = content.present? && (new_record? || will_save_change_to_content?)
    return unless check_title || check_content

    recent_blogs = Blog.where(user_id: user_id, created_at: 7.days.ago..Time.current)
    recent_blogs = recent_blogs.where.not(id: id) if persisted?
    if check_title && recent_blogs.exists?(title: title)
      errors.add(:base, 'このサークルでは、過去7日以内に同じタイトルのブログが投稿されています。')
    end
    if check_content && recent_blogs.exists?(content: content)
      errors.add(:base, 'このサークルでは、過去7日以内に同じ本文のブログが投稿されています。')
    end
  end

  def flag_suspicious_content
    return if moderation_status == "blocked"
    return unless new_record? || will_save_change_to_content? || will_save_change_to_title?

    reasons = moderation_rule_reasons
    if reasons.any?
      self.moderation_status = "review"
      self.moderation_reasons = ModerationReasonReport.snapshot(reasons)
      self.moderation_checked_at = Time.current
    end
  end

  public
  validates :title, presence: true
  validates :content, length: { minimum: 100}
  validates :user_id, presence: true
  validate :reject_recent_duplicates

	mount_uploader :image_01, ImageUploader
	mount_uploader :image_02, ImageUploader
	mount_uploader :image_03, ImageUploader
	mount_uploader :image_04, ImageUploader

	paginates_per 10

  scope :blog_sort, -> { order(created_at: "DESC").moderation_last }
  scope :list, -> (user_ids){publicly_visible.where(user_id: user_ids).includes(user: [:event, :prefecture]).blog_sort}


end
