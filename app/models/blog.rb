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
  belongs_to :user
  before_validation :flag_suspicious_content

  scope :publicly_visible, -> { where(moderation_status: "clear", user_id: User.publicly_visible.select(:id)) }

  def publicly_visible?
    moderation_status == "clear" && user.publicly_visible?
  end

  private

  def flag_suspicious_content
    return if moderation_status == "blocked"
    return unless new_record? || will_save_change_to_content? || will_save_change_to_title?

    body = ActionView::Base.full_sanitizer.sanitize([title, content].join(" "))
    links_without_japanese = body !~ User::JAPANESE_TEXT && body.scan(User::LINK_TEXT).length >= 2
    repeated_post = content.present? && Blog.where(content: content).where.not(id: id).limit(2).count >= 2
    rapid_posting = new_record? && user_id.present? && Blog.where(user_id: user_id).where("created_at >= ?", 1.hour.ago).limit(3).count >= 3
    self.moderation_status = "review" if links_without_japanese || repeated_post || rapid_posting
  end

  public
  validates :title, presence: true
  validates :content, length: { minimum: 100}
  validates :user_id, presence: true

	mount_uploader :image_01, ImageUploader
	mount_uploader :image_02, ImageUploader
	mount_uploader :image_03, ImageUploader
	mount_uploader :image_04, ImageUploader

	paginates_per 10

  scope :blog_sort, -> { order(created_at: "DESC") }
  scope :list, -> (user_ids){publicly_visible.where(user_id: user_ids).includes(user: [:event, :prefecture]).blog_sort}


end
