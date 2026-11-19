require 'test_helper'
require_relative '../support/chat_records'

class AttendanceAnswersTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    travel_to Time.zone.local(2026, 10, 17, 12)
    create_chat_records
    @circle.update!(unique_id: 'attendance-regression-circle')
    @today = schedule(Date.current, '今日の練習')
    @future = schedule(Date.tomorrow, '次の練習')
    @past = schedule(Date.yesterday, '過去の練習')
    @name = Name.create!(name: '出欠テスト')
    @answer = @name.name_schedules.create!(schedule: @today, answer: 1)
    @name.name_schedules.create!(schedule: @past, answer: 0)
  end

  teardown { travel_back }

  test 'organizer can copy a full chronological schedule with member venue and attendance link' do
    @today.update!(time_s: '18:50', time_e: '21:00', member_venue: '西中原中学校')
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    get attendances_path(@circle.unique_id), params: { tracking: 'omit-from-link' }

    assert_response :success
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_select 'meta[name="turbolinks-cache-control"][content="no-cache"]', count: 1
    assert_select 'details.attendance-schedule-share:not([open]) summary', text: 'スケジュール共有文を表示'
    assert_select 'details.attendance-schedule-share button[data-management-copy-button]', text: '全文をコピー'
    assert_select 'textarea[readonly][aria-label="スケジュール共有文"]' do |fields|
      assert_equal <<~TEXT.strip, fields.first.text.strip
        【スケジュール】

        10月17日(土) 18:50 - 21:00
        @西中原中学校

        10月18日(日) 時間未定
        @体育館

        ▼出欠の登録・編集
        https://circle-book.com#{attendances_path(@circle.unique_id)}
      TEXT
    end

    get attendances_path(@circle.unique_id, archive: 1)
    assert_response :success
    assert_select '.attendance-schedule-share', count: 0
  end

  test 'visitor and another circle organizer do not receive the schedule copy controls' do
    get attendances_path(@circle.unique_id)
    assert_response :success
    assert_select '.attendance-schedule-share', count: 0

    other = AdminUser.create!(email: 'another-owner@example.test', password: 'test-password-123', email_verified_at: Time.current)
    User.create!(@circle.attributes.except('id', 'created_at', 'updated_at', 'unique_id').merge(admin_user_id: other.id, name: '別のサークル'))
    post admin_user_session_path, params: { admin_user: { email: other.email, password: 'test-password-123' } }
    get attendances_path(@circle.unique_id)
    assert_response :success
    assert_select '.attendance-schedule-share', count: 0
  end

  test 'organizer is not offered an empty schedule to copy' do
    @today.update!(day: '2026-10-14')
    @future.update!(day: '2026-10-15')
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    get attendances_path(@circle.unique_id)
    assert_response :success
    assert_select '.attendance-schedule-share', count: 0
  end

  test 'selecting an existing name opens its answers and offers new upcoming dates' do
    get attendances_path(@circle.unique_id)
    assert_response :success
    assert_select "a[href='#{edit_attendance_path(@circle.unique_id, @name)}']"
    get edit_attendance_path(@circle.unique_id, @name)
    assert_response :success
    assert_select 'select[name$="[answer]"]', count: 2
    assert_select 'select[name$="[answer]"] option[selected][value="1"]', count: 1
    assert_select 'input[name$="[schedule_id]"]' do |inputs|
      assert_equal [@today.id, @future.id].sort, inputs.map { |input| input['value'].to_i }.sort
    end
    assert_select '.delete_btn a', text: /出欠テスト\s*さんの登録を削除する/
  end

  test 'capacity rules preserve existing participants and reject joining a full date' do
    @today.update!(recruitment_numbers: 1)
    @future.update!(recruitment_numbers: 1)
    other = Name.create!(name: '別の回答者')
    other.name_schedules.create!(schedule: @future, answer: 1)

    get edit_attendance_path(@circle.unique_id, @name)
    assert_response :success
    assert_select 'select[name$="[answer]"]', count: 1

    patch attendance_path(@circle.unique_id, @name), params: { name: {
      name: @name.name, name_schedules_attributes: {
        '0' => { id: @answer.id, schedule_id: @today.id, answer: '1', comment: '参加のまま' }
      }
    } }
    assert_redirected_to attendances_path(@circle.unique_id)
    assert_equal '参加のまま', @answer.reload.comment

    assert_no_difference 'NameSchedule.count' do
      patch attendance_path(@circle.unique_id, @name), params: { name: {
        name: @name.name, name_schedules_attributes: {
          '0' => { schedule_id: @future.id, answer: '1' }
        }
      } }
    end
    assert_redirected_to edit_attendance_path(@circle.unique_id, @name)
    assert_equal '既に満員の日程があります', flash[:notice]
  end

  test 'zero capacity means unlimited and invalid names redisplay the form' do
    @today.update!(recruitment_numbers: 0)
    patch attendance_path(@circle.unique_id, @name), params: { name: {
      name: '', name_schedules_attributes: {
        '0' => { id: @answer.id, schedule_id: @today.id, answer: '1' }
      }
    } }
    assert_response :success
    assert_equal '出欠テスト', @name.reload.name
    assert_select 'input[name="name[name]"][value=""]'
  end

  test 'answer changes and added dates are saved and can be reopened' do
    patch attendance_path(@circle.unique_id, @name), params: { name: {
      name: @name.name, name_schedules_attributes: {
        '0' => { id: @answer.id, schedule_id: @today.id, answer: '0', comment: '欠席します' },
        '1' => { schedule_id: @future.id, answer: '1' }
      }
    } }
    assert_redirected_to attendances_path(@circle.unique_id)
    assert_equal 0, @answer.reload.answer
    assert_equal '欠席します', @answer.comment
    assert_equal 1, @name.name_schedules.find_by!(schedule: @future).answer
    get edit_attendance_path(@circle.unique_id, @name)
    assert_response :success
  end

  private

  def schedule(day, title)
    @circle.schedules.create!(day: day.iso8601, title: title, venue: '体育館')
  end
end
