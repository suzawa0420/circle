require 'test_helper'
require_relative '../support/chat_records'

class ScheduleCopyTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    @circle.update!(recruitment: "初心者歓迎")
    @source = @circle.schedules.create!(day: '2026-12-29', title: '毎週の練習',
      venue: '世田谷区', member_venue: '体育館', venue_address: '東京都世田谷区1-1',
      time_s: '18:00', time_e: '20:00', cost: '500円', note: '<p>持ち物はシューズ</p>',
      recruitment_numbers: 12, recruitment: '募集終了', google_map: '地図情報')
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
  end

  test 'creation and owner detail provide both copy actions' do
    get new_user_schedule_path(@circle)
    assert_response :success
    assert_select "select[name=copy][required] option[value='#{@source.id}']"
    assert_select 'button[name=copy_mode][value=same]', text: '同じ内容でコピー'
    assert_select 'button[name=copy_mode][value=next_week]', text: '1週間後に同じ内容で作成'
    get user_schedule_path(@circle, @source)
    assert_response :success
    assert_select "a[href='#{new_user_schedule_path(@circle, copy: @source.id)}']"
    assert_select "a[href='#{new_user_schedule_path(@circle, copy: @source.id, copy_mode: :next_week)}']"
  end

  test 'ordinary copy keeps the day blank and copies editable contents' do
    get new_user_schedule_path(@circle), params: { copy: @source.id }
    assert_response :success
    assert_select 'input[name="schedule[day]"]' do |inputs|
      assert inputs.first['value'].blank?
    end
    assert_copied_contents
  end

  test 'weekly copy advances seven calendar days across year and leap month boundaries without saving' do
    ['2026-12-29', '2028-02-25'].each do |day|
      @source.update!(day: day)
      assert_no_difference 'Schedule.count' do
        get new_user_schedule_path(@circle), params: { copy: @source.id, copy_mode: 'next_week' }
      end
      assert_response :success
      assert_select "input[name='schedule[day]'][value='#{(Date.parse(day) + 7).iso8601}']"
      assert_copied_contents
    end
  end

  test 'copy saves the date and contents edited by the owner and leaves the original intact' do
    attributes = @source.attributes.slice('venue', 'title', 'cost', 'member_venue', 'venue_address',
      'note', 'recruitment_numbers', 'google_map').merge(day: '2027-01-07', title: '翌週の練習', time_s: '19:00', time_e: '21:00')
    assert_difference 'Schedule.count', 1 do
      post user_schedules_path(@circle), params: { copy: @source.id, schedule: attributes }
    end
    assert_redirected_to user_schedules_path(@circle)
    created = @circle.schedules.order(:id).last
    assert_equal '2027-01-07', created.day
    assert_equal '翌週の練習', created.title
    assert_equal '19:00', created.time_s.strftime('%H:%M')
    assert_equal 12, created.recruitment_numbers
    assert_equal @source.note, created.note
    assert_equal @source.google_map, created.google_map
    assert_equal '2026-12-29', @source.reload.day
    assert_equal '毎週の練習', @source.title
    assert_empty created.name_schedules
  end

  test 'validation errors retain edits and copy source' do
    post user_schedules_path(@circle), params: { copy: @source.id,
      schedule: { day: '2027-01-05', title: '', venue: '変更したエリア', recruitment_numbers: 8 } }
    assert_response :success
    assert_select 'input[name="schedule[title]"][value=""]'
    assert_select 'input[name="schedule[venue]"][value="変更したエリア"]'
    assert_select 'select[name="schedule[recruitment_numbers]"] option[selected][value="8"]'
    assert_select "input[name=copy][value='#{@source.id}']"
    assert_select 'button[name=copy_mode]', count: 2
  end

  test 'copy previews and retains the original image when no replacement is uploaded' do
    require 'base64'
    require 'tempfile'
    file = Tempfile.new(['schedule-copy', '.gif'])
    file.binmode
    file.write(Base64.decode64('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'))
    file.rewind
    @source.top_image = file
    @source.save!
    get new_user_schedule_path(@circle), params: { copy: @source.id, copy_mode: 'next_week' }
    assert_response :success
    assert_select '#img_field_header img' do |images|
      assert_equal @source.top_image.url, images.first['src']
    end
    post user_schedules_path(@circle), params: { copy: @source.id,
      schedule: { day: '2027-01-05', title: @source.title, venue: @source.venue } }
    assert_redirected_to user_schedules_path(@circle)
    created = @circle.schedules.order(:id).last
    assert created.top_image.present?
    assert_equal File.binread(@source.top_image.path), File.binread(created.top_image.path)
  ensure
    created&.top_image&.remove!
    @source.top_image.remove!
    file&.close!
  end

  test 'another circle cannot be used as a copy source for either read or write' do
    other_circle = User.create!(@circle.attributes.except('id', 'created_at', 'updated_at', 'unique_id'))
    other = other_circle.schedules.create!(day: '2027-01-01', title: '別サークル', venue: '別エリア')
    assert_raises(ActiveRecord::RecordNotFound) do
      get new_user_schedule_path(@circle), params: { copy: other.id, copy_mode: 'next_week' }
    end
    assert_no_difference 'Schedule.count' do
      assert_raises(ActiveRecord::RecordNotFound) do
        post user_schedules_path(@circle), params: { copy: other.id,
          schedule: { day: '2027-01-08', title: 'コピー', venue: 'エリア' } }
      end
    end
  end

  private

  def assert_copied_contents
    %w[venue title cost member_venue venue_address google_map note].each do |field|
      assert_select "input[name='schedule[#{field}]']" do |inputs|
        assert_equal @source.public_send(field), inputs.first['value']
      end
    end
    assert_select 'input[name="schedule[time_s]"][value="18:00:00.000"]'
    assert_select 'input[name="schedule[time_e]"][value="20:00:00.000"]'
    assert_select 'select[name="schedule[recruitment_numbers]"] option[selected][value="12"]'
    assert_select "input[name=copy][value='#{@source.id}']"
  end
end
