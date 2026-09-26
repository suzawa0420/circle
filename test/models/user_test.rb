# == Schema Information
#
# Table name: users
#
#  id                :bigint           not null, primary key
#  age               :string
#  appeal            :text
#  area              :string
#  average_age       :string
#  cb_point          :float            default(0.0), not null
#  contact           :string
#  cost              :string
#  decade_age        :integer
#  email             :string
#  failed_attempts   :integer          default(0), not null
#  foundation        :string
#  gallery_01        :string
#  gallery_02        :string
#  gallery_03        :string
#  gallery_04        :string
#  goal              :string
#  grouping          :string
#  header_image      :string
#  image_name        :string
#  impressions_count :integer          default(0)
#  instagram         :string
#  item              :string
#  last_post         :string
#  line_count        :integer          default(0)
#  locked_at         :datetime
#  mail_count        :integer          default(0)
#  member            :string
#  name              :string
#  ng_account        :string
#  password          :string
#  pic_header        :string
#  pic_profile       :string
#  point             :string
#  prefecture        :string
#  recruitment       :string
#  requirement       :text
#  review_permit     :boolean          default(TRUE)
#  review_score      :string
#  schedule          :string
#  sent_count        :integer
#  switch            :string
#  template          :text
#  twitter           :string
#  unlock_token      :string
#  user_time         :string
#  web               :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  admin_user_id     :bigint
#  category_id       :string
#  event_id          :integer
#  line_id           :string
#  prefecture_id     :bigint
#  prefecture_sub_id :integer
#  unique_id         :string
#  user_id           :string
#
# Indexes
#
#  index_users_on_admin_user_id  (admin_user_id)
#  index_users_on_prefecture_id  (prefecture_id)
#  index_users_on_unlock_token   (unlock_token) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (prefecture_id => prefectures.id)
#
require 'test_helper'

class UserTest < ActiveSupport::TestCase
  test "publication requires a useful introduction and activity details" do
    user = User.new(name: "地域サークル", event_id: 1, prefecture_id: 1, switch: "募集中",
      area: "世田谷区", schedule: "毎週土曜日", appeal: "<p>#{'地域で活動しています。' * 12}</p>")

    user.valid?
    assert_equal "published", user.publication_status
    assert_empty user.missing_publication_fields

    user.area = "  "
    user.valid?
    assert_equal "draft", user.publication_status
    assert_includes user.missing_publication_fields, "活動場所"
  end

  test "English alone is not treated as spam without links" do
    user = User.new(appeal: "We meet each weekend to play basketball and welcome beginners.")
    user.valid?
    assert_equal "clear", user.moderation_status

    user.appeal = "Join https://spam.example and https://other.example"
    user.valid?
    assert_equal "review", user.moderation_status
  end

  test "one link with www is counted once" do
    user = User.new(appeal: "Visit https://www.example.com for practice details")
    user.valid?
    assert_equal "clear", user.moderation_status
  end
end
