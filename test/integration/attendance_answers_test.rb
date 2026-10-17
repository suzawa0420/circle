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
