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
require 'test_helper'

class BlogTest < ActiveSupport::TestCase
  test "link-heavy non-Japanese posts wait for review" do
    blog = Blog.new(title: "Weekly practice", content: "Read https://spam.example and https://other.example " * 4)
    blog.valid?
    assert_equal "review", blog.moderation_status
  end
end
