require 'test_helper'
require_relative '../support/chat_records'

class ScheduleCheckInsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    travel_to Time.utc(2026, 11, 21, 15) # 00:00 on November 22 in Japan
    create_chat_records
    @circle.update!(unique_id: 'ordinary-attendance-link')
    @event = event(@circle, '今日のバスケ')
    @yes = answer(@event, '参加予定', 1, comment: '公開しない回答コメント')
    @no = answer(@event, '不参加の人', 0)
    @future = event(@circle, '明日のバスケ', day: '2026-11-23')
    @cancelled = event(@circle, '中止になったバスケ', recruitment: '中止')
    @other_circle = User.create!(@circle.attributes.except('id', 'created_at', 'updated_at', 'unique_id').merge(name: '別サークル'))
    @foreign = event(@other_circle, '別サークルのイベント')
    @foreign_yes = answer(@foreign, '別の参加者', 1)
  end

  teardown { travel_back }

  def event(circle, title, day: '2026-11-22', **attributes)
    circle.schedules.create!(title: title, day: day, venue: '川崎市', member_venue: '非公開の会場', time_s: '10:30', **attributes)
  end

  def answer(schedule, name, status, **attributes)
    schedule.name_schedules.create!(name: Name.create!(name: name), answer: status, **attributes)
  end

  def sign_in(owner = @owner)
    post admin_user_session_path, params: { admin_user: { email: owner.email, password: 'test-password-123' } }
  end

  def token
    @circle.attendance_check_in_token || begin
      @circle.update!(attendance_check_in_token: SecureRandom.urlsafe_base64(24))
      @circle.attendance_check_in_token
    end
  end

  test 'organizer opts in and the same QR is shown on multiple event management pages' do
    assert_nil @circle.attendance_check_in_token
    get manage_attendance_user_schedule_path(@circle, @event)
    assert_response :redirect
    sign_in
    get manage_attendance_user_schedule_path(@circle, @event)
    assert_response :success
    assert_select '[data-attendance-qr]', false
    assert_select '#day-check-ins button', text: '受付QRコードを発行'
    post enable_check_in_user_schedule_path(@circle, @event)
    assert_response :see_other
    key = @circle.reload.attendance_check_in_token
    assert_match(/\A[A-Za-z0-9_-]{32}\z/, key)
    post enable_check_in_user_schedule_path(@circle, @future)
    assert_equal key, @circle.reload.attendance_check_in_token
    get manage_attendance_user_schedule_path(@circle, @future)
    assert_not_includes response.body, key
    assert_select 'a[href=?]', check_in_qr_user_schedule_path(@circle, @future)
    get check_in_qr_user_schedule_path(@circle, @future)
    assert_response :success
    assert_equal 'no-referrer', response.headers['Referrer-Policy']
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_select 'script[src^="http"]', false
    assert_select '[data-attendance-qr][data-url=?]', "https://circle-book.com#{circle_check_in_path(token: key)}"
    post enable_check_in_user_schedule_path(@circle, @event), params: { reissue: '1' }
    assert_equal key, @circle.reload.attendance_check_in_token
    post enable_check_in_user_schedule_path(@circle, @event), params: { reissue: '1', confirm_reissue: '1' }
    assert_response :see_other
    assert_not_equal key, @circle.reload.attendance_check_in_token
    get circle_check_in_path(token: key)
    assert_response :not_found
  end

  test 'one JST event opens directly, and participant pages show only eligible names' do
    get circle_check_in_path(token: token)
    assert_response :success
    assert_select 'h2', text: @event.title
    assert_select 'button', text: @yes.name.name
    assert_select 'button', text: @no.name.name, count: 0
    [@yes.comment, @foreign_yes.name.name, @event.member_venue, @future.title, @cancelled.title].each do |private_text|
      assert_not_includes response.body, private_text
    end
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_equal 'noindex, nofollow, noarchive', response.headers['X-Robots-Tag']
    assert_equal 'no-referrer', response.headers['Referrer-Policy']
    assert_equal '/ci?token=[FILTERED]', request.filtered_path
    assert_select 'script', false
  end

  test 'multiple JST events are selected by event and closed days do not list participants' do
    second = event(@circle, '午後のバスケ', time_e: '20:00')
    get circle_check_in_path(token: token)
    assert_select 'a[href=?]', circle_check_in_event_path(second, token: token), text: /午後のバスケ.*20:00.*川崎市/m
    assert_select 'a[href=?]', circle_check_in_event_path(@event, token: token)
    assert_not_includes response.body, @yes.name.name
    travel_to Time.utc(2026, 11, 21, 14, 59)
    get circle_check_in_path(token: token)
    assert_response :success
    assert_select 'p', text: '本日チェックインを受け付けているイベントはありません。'
    assert_not_includes response.body, @yes.name.name
  end

  test 'choosing one of two same-day events lists only that event’s names' do
    second = event(@circle, '午後のバスケ')
    second_yes = answer(second, '午後だけ来る人', 1)
    get circle_check_in_event_path(second, token: token)
    assert_response :success
    assert_select 'button', text: second_yes.name.name
    assert_not_includes response.body, @yes.name.name
    get circle_check_in_event_path(@event, token: token)
    assert_response :success
    assert_select 'button', text: @yes.name.name
    assert_not_includes response.body, second_yes.name.name
  end

  test 'a day with only a cancelled event shows no names even with valid QR' do
    @event.update!(day: '2026-11-24')
    cancelled_yes = answer(@cancelled, '中止回の参加予定者', 1)
    get circle_check_in_path(token: token)
    assert_response :success
    assert_select 'p', text: '本日チェックインを受け付けているイベントはありません。'
    assert_not_includes response.body, cancelled_yes.name.name
    get circle_check_in_event_path(@cancelled, token: token)
    assert_response :not_found
    assert_not_includes response.body, cancelled_yes.name.name
  end

  test 'confirmation is separate, check-in is idempotent and does not edit RSVP' do
    assert_no_difference('ScheduleCheckIn.count') do
      post confirm_circle_check_in_path(@event, token: token), params: { name_id: @yes.name_id }
      assert_response :success
      assert_select 'h1', text: '名前の確認'
    end
    assert_difference('ScheduleCheckIn.count', 1) do
      2.times do
        post circle_check_in_event_path(@event, token: token), params: { name_id: @yes.name_id }
        assert_response :success
        assert_select 'h1', text: 'チェックインが完了しました'
      end
    end
    assert_equal 1, @yes.reload.answer
    @yes.update!(answer: 0)
    assert_equal 1, @event.schedule_check_ins.count
    @yes.destroy!
    assert_equal '参加予定', @event.schedule_check_ins.sole.display_name
    sign_in
    get manage_attendance_user_schedule_path(@circle, @event)
    assert_select '#day-check-ins h3', text: 'チェックイン済み 1名'
    assert_difference('ScheduleCheckIn.count', -1) do
      delete remove_check_in_user_schedule_path(@circle, @event, check_in_id: @event.schedule_check_ins.sole.id)
      assert_response :see_other
    end
  end

  test 'future, cancelled, foreign and nonattending submissions are rejected' do
    assert_no_difference('ScheduleCheckIn.count') do
      [[@future, @yes], [@cancelled, @yes], [@foreign, @foreign_yes], [@event, @foreign_yes], [@event, @no]].each do |schedule, attendance|
        post circle_check_in_event_path(schedule, token: token), params: { name_id: attendance.name_id }
        assert_response :not_found
        assert_not_includes response.body, attendance.name.name
      end
    end
  end

  test 'anonymous and unrelated owners cannot enable or correct QR check-ins' do
    check_in = @event.schedule_check_ins.create!(name_id: @yes.name_id, display_name: '参加予定', checked_in_at: Time.current)
    path = remove_check_in_user_schedule_path(@circle, @event, check_in_id: check_in.id)
    delete path
    assert_response :redirect
    other = AdminUser.create!(email: 'unrelated-owner@example.test', password: 'test-password-123', email_verified_at: Time.current)
    User.create!(@circle.attributes.except('id', 'created_at', 'updated_at', 'unique_id').merge(name: '別の主催者', admin_user: other))
    sign_in(other)
    post enable_check_in_user_schedule_path(@circle, @event)
    assert_response :forbidden
    delete path
    assert_response :forbidden
    assert_nil @circle.reload.attendance_check_in_token
    assert ScheduleCheckIn.exists?(check_in.id)
  end

  test 'another organizer cannot view a generated QR or its stored attendance history' do
    check_in = @event.schedule_check_ins.create!(name_id: @yes.name_id, display_name: '保護対象の受付実績', checked_in_at: Time.current)
    key = token
    other = AdminUser.create!(email: 'unrelated-reader@example.test', password: 'test-password-123', email_verified_at: Time.current)
    User.create!(@circle.attributes.except('id', 'created_at', 'updated_at', 'unique_id', 'attendance_check_in_token').merge(name: '別の主催者', admin_user: other))
    sign_in(other)

    get check_in_qr_user_schedule_path(@circle, @event)
    assert_response :forbidden
    assert_not_includes response.body, key

    get manage_attendance_user_schedule_path(@circle, @event)
    assert_not_equal 200, response.status
    assert_not_includes response.body, check_in.display_name
  end

  test 'matching organizer has a prominent check-in link on the existing RSVP page without an event' do
    @circle.schedules.destroy_all
    sign_in
    get attendances_path(@circle.unique_id)
    assert_response :success
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_select 'header.attendance-heading + section[aria-label=?] a[href=?]', '主催者向け当日チェックイン', user_check_in_qr_path(@circle), text: /当日チェックインのQR・URLを表示/
    assert_select 'a[href=?]', new_attendance_path(@circle.unique_id)
    get user_check_in_qr_path(@circle)
    assert_response :success
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_select 'button', text: '受付QRコードを発行'
    assert_select '[data-attendance-qr]', false
    assert_nil @circle.reload.attendance_check_in_token
    post user_check_in_qr_path(@circle)
    assert_redirected_to user_check_in_qr_path(@circle)
    key = @circle.reload.attendance_check_in_token
    assert_match(/\A[A-Za-z0-9_-]{32}\z/, key)
    follow_redirect!
    assert_select '[data-attendance-qr][data-url=?]', "https://circle-book.com#{circle_check_in_path(token: key)}"
    assert_select 'label', text: '当日チェックイン受付URL'
    assert_select 'button', text: '受付URLをコピー'
    assert_select 'a[href=?]', attendances_path(@circle.unique_id), text: '出欠確認に戻る'
    post user_check_in_qr_path(@circle)
    assert_equal key, @circle.reload.attendance_check_in_token
  end

  test 'anonymous members and unrelated organizers keep existing RSVP access but cannot get or issue a QR' do
    key = token
    get attendances_path(@circle.unique_id)
    assert_response :success
    assert_select 'a[href=?]', new_attendance_path(@circle.unique_id)
    assert_select 'a[href=?]', user_check_in_qr_path(@circle), count: 0
    assert_not_includes response.body, key
    get user_check_in_qr_path(@circle)
    assert_response :redirect
    post user_check_in_qr_path(@circle)
    assert_response :redirect
    other = AdminUser.create!(email: 'unrelated-entry@example.test', password: 'test-password-123', email_verified_at: Time.current)
    User.create!(@circle.attributes.except('id', 'created_at', 'updated_at', 'unique_id', 'attendance_check_in_token').merge(name: '別の主催者', admin_user: other))
    sign_in(other)
    get attendances_path(@circle.unique_id)
    assert_response :success
    assert_select 'a[href=?]', new_attendance_path(@circle.unique_id)
    assert_select 'a[href=?]', user_check_in_qr_path(@circle), count: 0
    assert_not_includes response.body, key
    get user_check_in_qr_path(@circle)
    assert_response :forbidden
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_not_includes response.body, key
    post user_check_in_qr_path(@circle), params: { reissue: '1', confirm_reissue: '1' }
    assert_response :forbidden
    assert_equal key, @circle.reload.attendance_check_in_token
    assert_equal 1, @yes.reload.answer
  end

end
