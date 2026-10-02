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
require_relative '../../db/migrate/20260927000000_review_circle_profiles_without_japanese_kana'

require_relative '../../db/migrate/20261002000000_publish_circles_without_activity_details'

class UserTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test "regional scopes preserve filters from parent listing levels" do
    category = Category.create!(name: "球技", kana: "ball-sports", order: "1")
    basketball = Event.create!(name: "バスケ", ruby: "basketball", category: category, order: "1")
    tennis = Event.create!(name: "テニス", ruby: "tennis", category: category, order: "2")
    kanagawa = Prefecture.create!(name: "神奈川県", kana: "kanagawa", order: "14", sort: 14)
    tokyo = Prefecture.create!(name: "東京都", kana: "tokyo", order: "13", sort: 13)
    nationwide = Prefecture.create!(id: 50, name: "全国", kana: "all", order: "50", sort: 50)
    now = Time.current

    records = [
      { name: "神奈川バスケ", event_id: basketball.id, prefecture_id: kanagawa.id },
      { name: "第2地域が神奈川のバスケ", event_id: basketball.id, prefecture_id: tokyo.id, prefecture_sub_id: kanagawa.id },
      { name: "全国バスケ", event_id: basketball.id, prefecture_id: nationwide.id },
      { name: "神奈川テニス", event_id: tennis.id, prefecture_id: kanagawa.id },
      { name: "第2地域が神奈川のテニス", event_id: tennis.id, prefecture_id: tokyo.id, prefecture_sub_id: kanagawa.id },
      { name: "全国テニス", event_id: tennis.id, prefecture_id: nationwide.id }
    ].map do |attributes|
      { prefecture_sub_id: nil, created_at: now, updated_at: now }.merge(attributes)
    end
    inserted = User.insert_all!(records, returning: %w[id name])
    ids = inserted.rows.to_h { |id, name| [name, id] }

    prefecture_results = User.where(event_id: basketball.id).where_pref(kanagawa.id).pluck(:id)
    assert_equal ["神奈川バスケ", "第2地域が神奈川のバスケ", "全国バスケ"].map { |name| ids.fetch(name) }.sort,
      prefecture_results.sort

    city = City.create!(name: "横浜市", city_kana: "yokohama", prefecture: kanagawa)
    UsersCity.create!(user_id: ids.fetch("神奈川バスケ"), city: city)
    UsersCity.create!(user_id: ids.fetch("神奈川テニス"), city: city)

    city_results = User.where(event_id: basketball.id).where_city(city).pluck(:id)
    assert_equal ["神奈川バスケ", "全国バスケ"].map { |name| ids.fetch(name) }.sort, city_results.sort
  end

  test "publication allows missing activity time and place" do
    user = User.new(name: "地域サークル", event_id: 1, prefecture_id: 1, switch: "募集中",
      area: "世田谷区", schedule: "毎週土曜日", appeal: "<p>#{'地域で活動しています。' * 12}</p>")

    user.valid?
    assert_equal "published", user.publication_status
    assert_empty user.missing_publication_fields

    [{ area: nil }, { schedule: "" }, { area: "  ", schedule: "  " }].each do |attributes|
      user.assign_attributes(attributes)
      user.valid?
      assert_equal "published", user.publication_status
      assert_empty user.missing_publication_fields
    end

    user.appeal = "短い紹介"
    user.valid?
    assert_equal "draft", user.publication_status
    assert_includes user.missing_publication_fields, "サークルの詳細情報（100文字以上）"

    user.name = ""
    assert_includes user.missing_publication_fields, "サークル名"
  end

  test "backfill publishes eligible drafts and their blogs while preserving moderation" do
    category = Category.create!(name: "球技", kana: "ball-sports", order: "1")
    event = Event.create!(name: "バスケ", ruby: "basketball", category: category, order: "1")
    prefecture = Prefecture.create!(name: "東京都", kana: "tokyo", order: "13", sort: 13)
    owner = AdminUser.create!(email: "optional-activity@example.test", password: "test-password-123")
    attributes = { event: event, prefecture: prefecture, category: category, admin_user: owner,
      name: "地域バスケサークル", switch: "募集中", appeal: "地域で楽しく活動しています。" * 10 }
    circles = [{ area: nil, schedule: "土曜日" }, { area: "体育館", schedule: "" },
      { area: "  ", schedule: nil }].map { |activity| User.create!(**attributes, **activity) }
    circles.each { |circle| circle.update_column(:publication_status, "draft") }
    blog = Blog.create!(user: circles.last, title: "活動記録", content: "地域で活動しました。" * 15)
    incomplete = User.create!(**attributes, appeal: "<p>短い紹介</p>" + " " * 120)
    missing_name = User.create!(**attributes)
    missing_name.update_columns(name: "  ", publication_status: "draft")
    reviewed = User.create!(**attributes, moderation_status: "review")
    reviewed.update_column(:publication_status, "draft")
    blocked = User.create!(**attributes, moderation_status: "blocked")
    blocked.update_column(:publication_status, "draft")

    assert_not_includes Blog.publicly_visible, blog
    migration = PublishCirclesWithoutActivityDetails.new
    migration.up
    migration.up # Re-running must not change moderation or already published records.

    circles.each do |circle|
      assert_equal "published", circle.reload.publication_status
      assert circle.publicly_visible?
      assert_includes User.publicly_visible, circle
    end
    assert blog.reload.publicly_visible?
    assert_includes Blog.publicly_visible, blog
    [incomplete, missing_name].each { |circle| assert_equal "draft", circle.reload.publication_status }
    [reviewed, blocked].each do |circle|
      assert_not circle.reload.publicly_visible?
      assert_not_includes User.publicly_visible, circle
    end
    assert_equal "review", reviewed.moderation_status
    assert_equal "blocked", blocked.moderation_status

    migration.down
    circles.each { |circle| assert_equal "draft", circle.reload.publication_status }
    assert_not_includes Blog.publicly_visible, blog
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

  test "Chinese characters without Japanese kana do not clear a circle profile" do
    user = User.new(name: "bd333", appeal: "বাংলা স্পোর্টস এবং 火箭 网站 https://bd333-bd.fun " * 5)
    user.valid?
    assert_equal "review", user.moderation_status
  end

  test "backfill hides published circles with Chinese characters but no Japanese kana" do
    category = Category.create!(name: "球技", kana: "ball-sports", order: "1")
    event = Event.create!(name: "バスケ", ruby: "basketball", category: category, order: "1")
    prefecture = Prefecture.create!(name: "東京都", kana: "tokyo", order: "1", sort: 1)
    owner = AdminUser.create!(email: "chinese-profile-owner@example.test", password: "test-password-123")
    attributes = { event: event, prefecture: prefecture, category: category, admin_user: owner,
      switch: "募集中", area: "オンライン", schedule: "毎週土曜日" }
    spam = User.create!(**attributes, name: "bd333", appeal: "বাংলা স্পোর্টস এবং 火箭 网站 https://bd333-bd.fun " * 5)
    japanese = User.create!(**attributes, name: "地域バスケサークル", appeal: "地域で楽しく活動しています。" * 10)
    blog = Blog.create!(user: spam, title: "活動記録", content: "地域で活動しました。" * 15)
    spam.update_column(:moderation_status, "clear") # Simulate a circle screened under the old rule.
    assert_includes User.publicly_visible, spam
    assert_includes Blog.publicly_visible, blog

    ReviewCircleProfilesWithoutJapaneseKana.new.up

    assert_equal "review", spam.reload.moderation_status
    assert_equal "clear", japanese.reload.moderation_status
    assert_not spam.publicly_visible?
    assert_not_includes User.publicly_visible, spam
    assert_not_includes Blog.publicly_visible, blog
    assert_includes User.publicly_visible, japanese
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
