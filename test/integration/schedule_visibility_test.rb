require 'test_helper'
require_relative '../support/chat_records'

class ScheduleVisibilityTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    travel_to Time.zone.local(2026, 10, 27, 12)
    create_chat_records
    @schedule = @circle.schedules.create!(day: '2026-10-30', title: '確認待ちの活動タイトル', venue: '検証用の活動会場')
    @circle.update_columns(moderation_status: 'review')
  end
  teardown { travel_back }

  test 'review circle calendar and activity detail reject anonymous HTML and JSON requests' do
    schedule_paths.each do |path|
      assert_raises(ActiveRecord::RecordNotFound) { get path }
      assert_raises(ActiveRecord::RecordNotFound) { get path, as: :json }
    end
  end

  test 'other nonpublic circle states use the same public boundary' do
    [{ moderation_status: 'blocked' }, { moderation_status: 'clear', publication_status: 'draft' },
     { moderation_status: 'clear', publication_status: 'published', ng_account: 'NG' }].each do |attributes|
      @circle.update_columns(attributes)
      schedule_paths.each { |path| assert_raises(ActiveRecord::RecordNotFound) { get path } }
    end
  end

  test 'the owning organizer can preview hidden schedules with private noindex responses' do
    login_owner
    assert_private_preview
    get manage_user_schedule_path(@circle, @schedule)
    assert_response :success
  end

  test 'an unpublished organizer also hides otherwise public schedules' do
    @circle.update_columns(moderation_status: 'clear')
    @owner.update_columns(check: AdminUser::SHADOW_BANNED_CHECK)
    schedule_paths.each { |path| assert_raises(ActiveRecord::RecordNotFound) { get path } }
  end

  test 'the existing webmaster can preview hidden schedules privately' do
    webmaster = Webmaster.create!(id: 1, email: 'schedule-visibility-master@example.test', password: 'test-password-123')
    post webmaster_session_path, params: { webmaster: { email: webmaster.email, password: 'test-password-123' } }
    assert_private_preview
  end

  test 'another organizer and an existing participant cannot preview review schedules' do
    other_owner = AdminUser.create!(email: 'schedule-other-owner@example.test', password: 'test-password-123', email_verified_at: Time.current)
    other_circle = @circle.dup
    other_circle.assign_attributes(admin_user: other_owner, name: '別の主催者のサークル')
    other_circle.save!
    post admin_user_session_path, params: { admin_user: { email: other_owner.email, password: 'test-password-123' } }
    schedule_paths.each { |path| assert_raises(ActiveRecord::RecordNotFound) { get path } }
    delete destroy_admin_user_session_path
    post member_session_path, params: { member: { email: @member.email, password: 'test-password-123' } }
    schedule_paths.each { |path| assert_raises(ActiveRecord::RecordNotFound) { get path } }
  end

  test 'public schedules remain readable and become hidden immediately when held' do
    @circle.update_columns(moderation_status: 'clear')
    schedule_paths.each do |path|
      get path
      assert_response :success
      assert_includes response.body, @schedule.title
    end
    @circle.update_columns(moderation_status: 'review')
    schedule_paths.each { |path| assert_raises(ActiveRecord::RecordNotFound) { get path } }
  end

  test 'review schedules stay outside discovery image API and sitemap populations' do
    assert_not_includes EventDayListing.public_schedules, @schedule
    assert_empty EventDaySitemap.each_path.to_a
    get ogp_user_schedule_path(@circle, @schedule, format: :png)
    assert_response :not_found
    get circles_path
    assert_response :success
    assert_select 'a[href=?]', circle_path(@circle), count: 0
    refute_includes response.body, @circle.name
    get circles_search_index_path, params: { detailed: '1', q: '検証' }
    assert_response :success
    assert_select 'a[href=?]', circle_path(@circle), count: 0
    refute_includes response.body, @circle.name
    get '/dates'
    assert_response :success
    assert_select 'a[href=?]', user_schedule_path(@circle, @schedule), count: 0
    refute_includes response.body, @schedule.title
  end

  private

  def schedule_paths
    [user_schedules_path(@circle), user_schedule_path(@circle, @schedule)]
  end

  def login_owner
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
  end

  def assert_private_preview
    schedule_paths.each do |path|
      get path
      assert_response :success
      assert_includes response.body, @schedule.title
      assert_equal 'private, no-store', response.headers['Cache-Control']
      assert_equal 'noindex, nofollow', response.headers['X-Robots-Tag']
    end
  end
end
