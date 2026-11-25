require 'test_helper'
require_relative '../support/chat_records'

class PublicCircleDatesAndReviewsDesignTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup { create_chat_records }

  test 'activity tab shows the public calendar inside the shared circle layout' do
    @circle.schedules.create!(day: '2026-11-29', title: '体験会',
      venue: '公開体育館', member_venue: '秘密の集合場所', time_s: '13:00', time_e: '15:00')
    get user_schedules_path(@circle), params: { month: '2026-11', date: '2026-11-29' }

    assert_response :success
    assert_select '.cb-public-circle__main .cb-circle-dates #schedule-calendar'
    assert_select '.cb-circle-dates #activity-list .schedule-calendar__event', count: 1
    assert_not_includes response.body, '秘密の集合場所'
  end

  test 'review tab shows aggregate and public cards with review metadata and keeps private actions private' do
    @circle.update_column(:review_score, 4.25)
    @circle.reviews.create!(member: @member, review: 1, comment: '最初の参加も楽しかったです。')
    @circle.reviews.create!(review: 0, comment: '自分とは少し違いました。')

    get user_reviews_path(@circle)

    assert_response :success
    assert_select '.cb-public-circle__main .cb-circle-reviews__score', text: '4.25'
    assert_select '.cb-circle-reviews__summary-details', text: /2件の口コミ/
    assert_select '.cb-circle-reviews__card', count: 2
    assert_select '.cb-circle-reviews > div.cb-circle-tab-heading > h1', text: '口コミ・評価'
    assert_select '.cb-circle-reviews__card > div.cb-circle-reviews__card-header + .cb-circle-reviews__body', count: 2
    assert_select '.cb-circle-reviews__avatar img', count: 2
    assert_select '.cb-circle-reviews__author a[href=?]', member_profile_path(@member)
    assert_select '.cb-circle-reviews__rating', text: '良かった'
    assert_select '.cb-circle-reviews__rating.is-negative', text: '残念だった'
    assert_select '.cb-circle-reviews__actions', count: 0
    assert_select '#review-request', count: 0
  end

  test 'empty circle review tab does not show a misleading rating' do
    get user_reviews_path(@circle)

    assert_response :success
    assert_select '.cb-circle-reviews__summary', count: 0
    assert_select '.cb-circle-reviews__notice', text: '口コミはまだありません。'
  end
end
