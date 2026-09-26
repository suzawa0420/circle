# == Schema Information
#
# Table name: place_reviews
#
#  id            :bigint           not null, primary key
#  access        :float
#  average_score :float
#  comment       :text
#  facility      :float
#  ip_address    :string
#  price         :float
#  reservation   :float
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  event_id      :integer
#  place_id      :bigint
#
# Indexes
#
#  index_place_reviews_on_place_id  (place_id)
#
# Foreign Keys
#
#  fk_rails_...  (place_id => places.id)
#
require 'test_helper'
require_relative '../../db/migrate/20260927010000_moderate_place_reviews'

class PlaceReviewTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test "comments without kana and SQL probes wait for review" do
    english = PlaceReview.new(comment: "Automated facility comment in English")
    english.valid?
    assert_equal "review", english.moderation_status

    probe = PlaceReview.new(comment: "設備は良いです SELECT x FROM PG_SLEEP(15)")
    probe.valid?
    assert_equal "review", probe.moderation_status

    japanese = PlaceReview.new(comment: "設備がきれいで使いやすいです。")
    japanese.valid?
    assert_equal "clear", japanese.moderation_status
  end

  test "backfill removes the confirmed facility spam and excludes other suspect ratings" do
    now = Time.current
    Place.insert_all!([
      { id: 1925, name: "対象施設", created_at: now, updated_at: now },
      { id: 1926, name: "別施設", created_at: now, updated_at: now }
    ])
    target = Place.find(1925)
    other = Place.find(1926)
    spam = PlaceReview.create!(place: target, comment: "SELECT x FROM PG_SLEEP(15)",
      facility: 0, reservation: 0, price: 0, access: 0)
    spam.update_columns(moderation_status: "clear", updated_at: Time.utc(2026, 9, 3))
    legitimate = PlaceReview.create!(place: target, comment: "設備がきれいで使いやすいです。",
      facility: 5, reservation: 5, price: 5, access: 5)
    other_spam = PlaceReview.create!(place: other, comment: "Automated English facility review",
      facility: 1, reservation: 1, price: 1, access: 1)
    other_spam.update_column(:moderation_status, "clear")
    target.update_columns(average_score: 2.5)
    other.update_columns(average_score: 1.0)

    ModeratePlaceReviews.new.backfill

    assert_not PlaceReview.exists?(spam.id)
    assert_equal "clear", legitimate.reload.moderation_status
    assert_equal 5.0, target.reload.average_score
    assert_equal 1, target.public_place_reviews.count
    assert_equal "review", other_spam.reload.moderation_status
    assert_nil other.reload.average_score
    assert_empty other.public_place_reviews
  end
end
