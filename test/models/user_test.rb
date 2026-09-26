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
require_relative '../../db/migrate/20260926010000_review_non_japanese_circle_profiles'

class UserTest < ActiveSupport::TestCase
  self.fixture_table_names = []
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

  test "English-only circle profiles wait for review even without links" do
    user = User.new(name: "Reddy Anna Book", area: "India", schedule: "6am to 8pm",
      appeal: "We meet each weekend to play basketball and welcome beginners." * 3)
    user.valid?
    assert_equal "review", user.moderation_status
  end

  test "English text with a Japanese introduction remains clear" do
    user = User.new(name: "International Basketball", appeal: "初心者も歓迎します。 We meet every weekend.")
    user.valid?
    assert_equal "clear", user.moderation_status
  end

  test "backfill hides previously published English-only circles" do
    category = Category.create!(name: "球技", kana: "ball-sports", order: "1")
    event = Event.create!(name: "バスケ", ruby: "basketball", category: category, order: "1")
    prefecture = Prefecture.create!(name: "東京都", kana: "tokyo", order: "1", sort: 1)
    owner = AdminUser.create!(email: "moderation-owner@example.test", password: "test-password-123")
    attributes = { event: event, prefecture: prefecture, category: category, admin_user: owner,
      switch: "募集中", area: "オンライン", schedule: "毎週土曜日" }
    spam = User.create!(**attributes, name: "Five88", appeal: "Visit our site for sports and offers. " * 5)
    japanese = User.create!(**attributes, name: "地域バスケサークル", appeal: "地域で楽しく活動しています。" * 10)
    blog = Blog.create!(user: spam, title: "活動記録", content: "地域で活動しました。" * 15)
    spam.update_column(:moderation_status, "clear") # Simulate a record screened under the old rule.
    assert_includes User.publicly_visible, spam
    assert_includes Blog.publicly_visible, blog

    ReviewNonJapaneseCircleProfiles.new.up

    assert_equal "review", spam.reload.moderation_status
    assert_equal "clear", japanese.reload.moderation_status
    assert_not spam.publicly_visible?
    assert_not_includes User.publicly_visible, spam
    assert_not_includes Blog.publicly_visible, blog
    assert_includes User.publicly_visible, japanese

    japanese.update!(appeal: "We meet each weekend to play basketball. " * 4)
    assert_equal "clear", japanese.moderation_status
    japanese.update!(name: "Five88")
    assert_equal "review", japanese.moderation_status
  end
end
