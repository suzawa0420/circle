require 'test_helper'
require_relative '../support/chat_records'

class CircleLevelNotificationTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    @circle.update!(user_time: Time.current.to_s)
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
  end

  test 'first visit establishes the current baseline without celebrating historical activity' do
    add_positive_review
    get "/users/#{@circle.id}/mypage"
    assert_response :success
    assert_select '#circle-level-up', count: 0
    assert_equal 2, @circle.reload.last_seen_circle_level
    assert_select '#circle-level-preview, [data-level-up-preview], [data-level-up-replay]', count: 0
  end

  test 'schedule creation crosses an integer level and celebrates once on return to the dashboard' do
    @circle.update!(last_seen_circle_level: 0)
    9.times { add_schedule }
    get "/users/#{@circle.id}/mypage"
    assert_select '#circle-level-up', count: 0
    post user_schedules_path(@circle), params: { schedule: { title: '次回の練習', venue: '体育館', day: (Date.current + 8).to_s } }
    assert_redirected_to user_schedules_path(@circle)
    get "/users/#{@circle.id}/mypage"
    assert_response :success
    assert_select '#circle-level-up .circle-level-up__old', text: /Lv\.\s*0/
    assert_select '#circle-level-up .circle-level-up__new', text: /Lv\.\s*1/
    assert_select "#circle-level-up a[href='#{new_user_schedule_path(@circle)}']", text: /スケジュールを登録する/
    assert_select '[data-level-up-close]', count: 2
    assert_select '#circle-level-up button[type="button"][data-level-up-replay]', count: 0
    assert_select '#circle-level-up [data-level-up-motion-status]', count: 0
    get "/users/#{@circle.id}/mypage"
    assert_select '#circle-level-up', count: 0
  end

  test 'reviews received while away combine into one notification and no other device sees it again' do
    @circle.update!(last_seen_circle_level: 0)
    2.times { add_positive_review }
    get "/users/#{@circle.id}/mypage"
    assert_select '.circle-level-up__new', text: /Lv\.\s*4/
    other_device = open_session
    other_device.post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    other_device.get "/users/#{@circle.id}/mypage"
    other_device.assert_select '#circle-level-up', count: 0
  end

  test 'decreases do not celebrate and subsequent increases use the lower baseline' do
    @circle.update!(last_seen_circle_level: 8)
    get "/users/#{@circle.id}/mypage"
    assert_select '#circle-level-up', count: 0
    assert_equal 0, @circle.reload.last_seen_circle_level
    add_positive_review
    get "/users/#{@circle.id}/mypage"
    assert_select '.circle-level-up__old', text: /Lv\.\s*0/
    assert_select '.circle-level-up__new', text: /Lv\.\s*2/
  end

  test 'maximum level does not repeat for surplus points' do
    assert_equal({ from: 99, to: 100 }, begin
      @circle.update!(last_seen_circle_level: 99)
      CircleLevelNotification.consume(@circle, level: 100)
    end)
    assert_nil CircleLevelNotification.consume(@circle, level: 102)
  end

  test 'another owner cannot consume the notification' do
    @circle.update!(last_seen_circle_level: 0)
    add_positive_review
    other = AdminUser.create!(email: 'other-level-owner@example.test', password: 'test-password-123', email_verified_at: Time.current)
    delete destroy_admin_user_session_path
    post admin_user_session_path, params: { admin_user: { email: other.email, password: 'test-password-123' } }
    get "/users/#{@circle.id}/mypage"
    assert_response :redirect
    assert_equal 0, @circle.reload.last_seen_circle_level
  end

  private

  def add_schedule
    @circle.schedules.create!(title: '週末の練習', venue: '体育館', day: (Date.current + 7).to_s)
  end

  def add_positive_review
    @circle.reviews.create!(review: 1, nickname: '参加者', comment: '楽しく活動できました。')
  end
end
