require 'test_helper'
require_relative '../support/chat_records'

class CircleProfileCompletionTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    @circle.update_columns(user_time: Time.current.to_s, last_post: 1.day.ago)
    login_owner
  end

  test 'incomplete profile shows only missing items with links to the actual edit controls' do
    get "/users/#{@circle.id}/mypage"
    assert_response :success
    assert_select '.dashboard-profile-completion__reward', text: /あと4項目で.*＋5レベル/m
    assert_select '.dashboard-profile-completion progress[max="7"][value="3"]'
    %w[img_field_header img_field_profile user_recruitment user_cost].each do |anchor|
      assert_select ".dashboard-profile-completion a[href='#{edit_user_path(@circle, anchor: anchor)}']"
    end
    assert_nil @circle.reload.profile_completion_rewarded_at
    get edit_user_path(@circle)
    %w[img_field_header img_field_profile circle-introduction user_area user_schedule user_recruitment user_cost].each do |anchor|
      assert_select "##{anchor}", count: 1
    end
  end

  test 'every one of the seven items is necessary and default image URLs do not count' do
    complete_profile
    { pic_header: nil, pic_profile: nil, appeal: '<p><br></p>', area: ' ', schedule: '', recruitment: nil, cost: '' }.each do |field, missing|
      original = @circle[field]
      @circle.update_columns(field => missing)
      assert_equal 1, CircleProfileCompletionReward.missing_items(@circle).size, field.to_s
      refute CircleProfileCompletionReward.grant(@circle), field.to_s
      assert_nil @circle.reload.profile_completion_rewarded_at
      @circle.update_columns(field => original)
    end
  end

  test 'free and zero costs count but short or invisible descriptions do not' do
    complete_profile
    ['無料', '0', '0円'].each do |cost|
      @circle.cost = cost
      assert_empty CircleProfileCompletionReward.missing_items(@circle)
    end
    ['あ' * 99, '<p>&nbsp; &#8203; </p>'].each do |appeal|
      @circle.appeal = appeal
      assert_equal ['circle-introduction'], CircleProfileCompletionReward.missing_items(@circle).map { |item| item[:anchor] }
    end
    @circle.appeal = '<p>' + 'あ' * 100 + '</p>'
    assert_empty CircleProfileCompletionReward.missing_items(@circle)
  end

  test 'legacy complete profile receives the bonus and celebration on its first dashboard visit' do
    complete_profile
    @circle.reviews.create!(review: 1, comment: '楽しく活動できました。')
    last_activity = @circle.reload.last_post
    get "/users/#{@circle.id}/mypage"
    assert_response :success
    assert_select '#circle-level-up-title', text: 'サークル情報の入力が完了しました！'
    assert_select '.circle-level-up__subtitle', text: '初回特典として5ポイント獲得！'
    assert_select '.circle-level-up__old', text: /Lv\.\s*2/
    assert_select '.circle-level-up__new', text: /Lv\.\s*7/
    assert_select ".circle-level-up__primary[href='#{new_user_schedule_path(@circle)}']"
    assert_select '.dashboard-level__value strong', text: '7'
    assert_select '.dashboard-level__breakdown tbody tr', text: /サークル情報入力特典.*5.0.*5.0/m
    assert_select '.dashboard-profile-completion', count: 0
    assert @circle.reload.profile_completion_rewarded_at
    assert @circle.profile_completion_notified_at
    assert_in_delta 7, @circle.cb_point
    assert_equal last_activity, @circle.last_post
    get "/users/#{@circle.id}/mypage"
    assert_select '#circle-level-up', count: 0
    another_device = open_session
    another_device.post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    another_device.get "/users/#{@circle.id}/mypage"
    another_device.assert_select '#circle-level-up', count: 0
  end

  test 'saving the final uploaded images awards once and waits until the dashboard to celebrate' do
    @circle.update!(recruitment: '初心者歓迎', cost: '無料', last_seen_circle_level: 0)
    image = -> { Rack::Test::UploadedFile.new(Rails.root.join('public/images/default.png'), 'image/png') }
    patch user_path(@circle), params: { user: { pic_header: image.call, pic_profile: image.call } }
    assert_redirected_to "/users/#{@circle.id}/edit2"
    assert @circle.reload.profile_completion_rewarded_at
    assert_nil @circle.profile_completion_notified_at
    assert @circle[:pic_header].present?
    assert @circle[:pic_profile].present?
    assert_in_delta 5, @circle.cb_point
    get "/users/#{@circle.id}/mypage"
    assert_select '.circle-level-up__old', text: /Lv\.\s*0/
    assert_select '.circle-level-up__new', text: /Lv\.\s*5/
    awarded_at = @circle.reload.profile_completion_rewarded_at
    patch user_path(@circle), params: { user: { cost: '500円' } }
    assert_equal awarded_at, @circle.reload.profile_completion_rewarded_at
    assert_in_delta 5, @circle.cb_point
    assert_not CircleProfileCompletionReward.grant(@circle)
  end

  test 'earned bonus survives removal and all subsequent score recalculations' do
    complete_profile
    stale_copy = User.find(@circle.id)
    assert CircleProfileCompletionReward.grant(@circle)
    refute CircleProfileCompletionReward.grant(stale_copy)
    awarded_at = @circle.profile_completion_rewarded_at
    @circle.update_columns(pic_header: nil, recruitment: '')
    CircleScoreUpdater.new.refresh(@circle)
    assert_in_delta 5, @circle.cb_point
    @circle.save!
    get "/users/#{@circle.id}/mypage"
    assert_select '.dashboard-profile-completion', count: 0
    @circle.update_columns(pic_header: 'header.jpg', recruitment: '初心者歓迎')
    refute CircleProfileCompletionReward.grant(@circle)
    assert_equal awarded_at, @circle.reload.profile_completion_rewarded_at
  end

  test 'bonus preserves the existing one-year inactivity rule' do
    complete_profile
    @circle.update_columns(user_time: 2.years.ago.to_s)
    get "/users/#{@circle.id}/mypage"
    assert @circle.reload.profile_completion_rewarded_at
    assert_in_delta 0, @circle.cb_point
    assert_select '.circle-level-up__levels[aria-label="5ポイント獲得"]'
    assert_select '.circle-level-up__old', count: 0
    @circle.update!(user_time: Time.current.to_s)
    CircleScoreUpdater.new.refresh(@circle)
    assert_in_delta 5, @circle.cb_point
  end

  test 'level cap and moderation penalties are preserved without claiming a false level increase' do
    complete_profile
    @circle.update_columns(last_seen_circle_level: 100)
    BacklinkRequest.create!(user: @circle, status: 'approved', placement_url: 'https://example.test/circle', submitted_at: Time.current)
    @circle.schedules.insert_all!(Array.new(900) { { user_id: @circle.id, title: '練習', day: (Date.current + 7).to_s, created_at: Time.current, updated_at: Time.current } })
    get "/users/#{@circle.id}/mypage"
    assert_select '.circle-level-up__old', count: 0
    assert_select '.circle-level-up__levels[aria-label="5ポイント獲得"]'
    assert_select '.dashboard-level__value strong', text: '100'
    assert_in_delta 105, @circle.reload.cb_point
    @owner.update!(check: 1)
    CircleScoreUpdater.new.refresh(@circle)
    assert_equal(-100, @circle.cb_point)
  end

  test 'public visits and other owners cannot grant or forge the reward' do
    complete_profile
    delete destroy_admin_user_session_path
    get circle_path(@circle)
    assert_nil @circle.reload.profile_completion_rewarded_at
    other = AdminUser.create!(email: 'profile-reward-other@example.test', password: 'test-password-123', email_verified_at: Time.current)
    post admin_user_session_path, params: { admin_user: { email: other.email, password: 'test-password-123' } }
    get "/users/#{@circle.id}/mypage"
    assert_response :redirect
    assert_nil @circle.reload.profile_completion_rewarded_at
    delete destroy_admin_user_session_path
    login_owner
    @circle.update_columns(pic_profile: nil)
    patch user_path(@circle), params: { user: { cost: '無料', profile_completion_rewarded_at: Time.current, profile_completion_notified_at: Time.current } }
    assert_nil @circle.reload.profile_completion_rewarded_at
    assert_nil @circle.profile_completion_notified_at
  end

  private

  def complete_profile
    @circle.update_columns(pic_header: 'header.jpg', pic_profile: 'profile.jpg', recruitment: '初心者歓迎', cost: '無料')
  end

  def login_owner
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
  end
end
