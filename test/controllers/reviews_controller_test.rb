require 'test_helper'
require_relative '../support/chat_records'

class ReviewsControllerTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords
  include Devise::Test::IntegrationHelpers

  setup do
    create_chat_records
    accept_conversation
    @conversation.submit_review!('member', member_evaluation)
    @conversation.submit_review!('owner', owner_evaluation)
    @chat_review = @circle.reviews.where.not(conversation_review_id: nil).sole
    @legacy = @circle.reviews.create!(member: @other_member, review: 0, comment: '以前参加した際の感想です。')
    @guest = @circle.reviews.create!(nickname: 'ゲスト', review: 1, comment: '楽しく参加できました。')
  end

  test 'circle owner can delete only their legacy member and guest reviews' do
    sign_in @owner
    get user_reviews_path(@circle)
    assert_response :success
    [@legacy, @guest].each do |review|
      assert_select ".review_delete a[href='#{user_review_path(@circle, review)}']", count: 1
    end
    assert_select ".review_delete a[href='#{user_review_path(@circle, @chat_review)}']", count: 0

    [@legacy, @guest].each do |review|
      assert_difference 'Review.count', -1 do
        delete user_review_path(@circle, review)
      end
      assert_redirected_to user_reviews_path(@circle)
      assert_equal @circle.reviews.average(:review).to_f * 5, @circle.reload.review_score.to_f
    end
    legacy_conversation = Conversation.find_by!(user: @circle, member: @other_member)
    assert legacy_conversation.legacy_member_review?
    legacy_conversation.send_message!('member', 'また参加したいです。')
    legacy_conversation.send_message!('owner', 'ぜひご参加ください。')
    assert_raises(Conversation::NotAllowed) { legacy_conversation.submit_review!('member', member_evaluation) }
  end

  test 'circle owner cannot delete chat reviews even through a direct request' do
    sign_in @owner
    assert_no_difference 'Review.count' do
      delete user_review_path(@circle, @chat_review)
    end
    assert_response :forbidden
    assert_nil @chat_review.conversation_review.reload.deleted_at
  end

  test 'other circle owners members and anonymous visitors cannot delete legacy reviews' do
    outsider = AdminUser.create!(email: 'other-owner@example.test', password: 'test-password-123')
    User.create!(@circle.attributes.except('id', 'created_at', 'updated_at', 'unique_id').merge('admin_user_id' => outsider.id, 'name' => '別のサークル'))
    unrelated_member = Member.create!(email: 'unrelated-member@example.test', nickname: '別の参加者', password: 'test-password-123')
    [nil, outsider, unrelated_member].each do |account|
      sign_in account if account
      get user_reviews_path(@circle)
      assert_response :success
      assert_select '.review_delete', count: 0
      [@legacy, @guest].each do |review|
        assert_no_difference 'Review.count' do
          delete user_review_path(@circle, review)
        end
        assert_response :forbidden
      end
      sign_out account if account
    end
  end

  test 'review authors and webmaster retain their existing deletion permissions' do
    sign_in @member
    get user_reviews_path(@circle)
    assert_select '.review_delete', count: 1
    assert_difference 'Review.count', -1 do
      delete user_review_path(@circle, @chat_review)
    end
    assert_response :redirect
    assert @chat_review.conversation_review.reload.deleted_at
    sign_out @member

    master = Webmaster.create!(id: 1, email: 'review-master@example.test', password: 'test-password-123')
    sign_in master
    get user_reviews_path(@circle)
    assert_select '.review_delete', count: 2
    assert_difference 'Review.count', -1 do
      delete user_review_path(@circle, @guest)
    end
    assert_response :redirect
  end
end
