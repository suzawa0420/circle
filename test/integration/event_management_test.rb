require 'test_helper'
require_relative '../support/chat_records'

class EventManagementTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    travel_to Time.zone.local(2026, 10, 26, 12)
    create_chat_records
    @circle.update!(unique_id: 'event-management-members', recruitment: '初心者歓迎')
    @event = @circle.schedules.create!(day: '2026-10-31', title: '今週のバスケ', venue: '川崎市',
      member_venue: 'メンバーの体育館', venue_address: 'メンバーの住所', recruitment_numbers: 16,
      time_s: '18:50', time_e: '21:00', note: '<div>室内シューズを持参</div>')
    @next = @circle.schedules.create!(day: '2026-11-07', title: '来月のバスケ', venue: '川崎市')
    @past = @circle.schedules.create!(day: '2026-10-24', title: '先週のバスケ', venue: '川崎市')
    @yes = Name.create!(name: '参加する人')
    @yes.name_schedules.create!(schedule: @event, answer: 1, comment: '少し遅れて参加します')
    @no = Name.create!(name: '欠席する人')
    @no.name_schedules.create!(schedule: @event, answer: 0)
    @unanswered = Name.create!(name: 'まだ回答していない人')
    @unanswered.name_schedules.create!(schedule: @past, answer: 1)
    @foreign_circle = User.create!(@circle.attributes.except('id', 'created_at', 'updated_at', 'unique_id').merge(name: '別サークル'))
    @foreign_event = @foreign_circle.schedules.create!(day: '2026-11-01', title: '別のイベント', venue: '別のエリア')
    @foreign_name = Name.create!(name: '別サークルだけの名前')
    @foreign_name.name_schedules.create!(schedule: @foreign_event, answer: 1)
  end

  teardown { travel_back }

  def sign_in
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
  end

  test 'owner list spans months, separates past, and exposes direct management actions' do
    sign_in
    get user_schedules_path(@circle)
    assert_response :success
    assert_select '.em-event', count: 2
    [@event, @next].each do |schedule|
      [manage_attendance_user_schedule_path(@circle, schedule), edit_user_schedule_path(@circle, schedule), duplicate_user_schedule_path(@circle, schedule)].each do |path|
        assert_select ".em-event a[href='#{path}']"
      end
    end
    assert_select '.em-events', text: /今週のバスケ.*来月のバスケ/m
    assert_select '.em-events', text: /先週のバスケ/, count: 0
    assert_select '.em-event:first-child .em-count', text: /参加 1 \/ 16名.*不参加 1 · 未回答 1/m
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_equal 'noindex, nofollow', response.headers['X-Robots-Tag']
    get user_schedules_path(@circle), params: { past: '1' }
    assert_select '.em-event', count: 1
    assert_select '.em-event h2', text: '先週のバスケ'
  end

  test 'dashboard directs organizers to event management instead of the member answer screen' do
    sign_in
    get "/users/#{@circle.id}/mypage"
    assert_response :success
    assert_select ".dashboard-action-grid a[href='#{user_schedules_path(@circle)}']", text: /イベント管理/
    assert_select ".dashboard-action-grid a[href='#{user_schedules_path(@circle, anchor: 'event-list')}']", text: /出欠管理/
  end

  test 'event attendance filters names and comments within this circle' do
    sign_in
    get manage_attendance_user_schedule_path(@circle, @event)
    assert_response :success
    assert_select '.em-answer-list li', count: 3
    assert_select '.em-answer-list', text: /少し遅れて参加します/
    assert_not_includes response.body, @foreign_name.name
    { 'yes' => @yes, 'no' => @no, 'unanswered' => @unanswered }.each do |filter, name|
      get manage_attendance_user_schedule_path(@circle, @event, answer: filter)
      assert_response :success
      assert_select '.em-answer-list li', count: 1
      assert_select ".em-answer-list a[href='#{edit_attendance_path(@circle.unique_id, name)}']", text: name.name
    end
  end

  test 'manager detail separates public copy content from member locations' do
    sign_in
    get manage_user_schedule_path(@circle, @event)
    assert_response :success
    assert_select '.em-facts-private', text: /メンバーの体育館.*メンバーの住所/m
    assert_select '[data-share-text]' do |fields|
      assert_not_includes fields.first.text, 'メンバーの'
    end
    assert_select '.em-card--member input[value=?]', "https://circle-book.com#{attendances_path(@circle.unique_id)}"
    assert_select '.em-card a[href=?]', user_schedule_path(@circle, @event)
    get user_schedule_path(@circle, @event)
    assert_not_includes response.body, 'メンバーの体育館'
    assert_not_includes response.body, 'メンバーの住所'
    assert_not_includes response.body, @circle.unique_id
  end

  test 'missing member URL still allows managing and editing legacy circles without inventing a public share URL' do
    @circle.update!(unique_id: nil)
    sign_in
    [user_schedules_path(@circle), new_user_schedule_path(@circle), edit_user_schedule_path(@circle, @event), manage_user_schedule_path(@circle, @event), manage_attendance_user_schedule_path(@circle, @event)].each do |path|
      get path
      assert_response :success
      assert_select 'input.em-copy-source[value*="/s//"]', count: 0
    end
  end

  test 'new management routes require the owning account and scope the event to the circle' do
    paths = %i[manage duplicate manage_attendance confirm_delete].map { |action| public_send("#{action}_user_schedule_path", @circle, @event) }
    paths.each do |path|
      get path
      assert_redirected_to new_admin_user_session_path
    end
    outsider = AdminUser.create!(email: 'event-manager-other@example.test', password: 'test-password-123', email_verified_at: Time.current)
    @foreign_circle.update!(admin_user: outsider)
    post admin_user_session_path, params: { admin_user: { email: outsider.email, password: 'test-password-123' } }
    paths.each do |path|
      get path
      assert_redirected_to circles_path
      assert_not_includes response.body, 'メンバーの住所'
    end
    delete destroy_admin_user_session_path
    sign_in
    %i[manage duplicate manage_attendance confirm_delete].each do |action|
      assert_raises(ActiveRecord::RecordNotFound) do
        get public_send("#{action}_user_schedule_path", @circle, @foreign_event)
      end
    end
  end

  test 'editing returns to management and an invalid capacity leaves the original untouched' do
    sign_in
    patch user_schedule_path(@circle, @event), params: { schedule: { title: '更新したバスケ', recruitment_numbers: 10 } }
    assert_redirected_to manage_user_schedule_path(@circle, @event)
    assert_equal '更新したバスケ', @event.reload.title
    @no.name_schedules.find_by!(schedule: @event).update!(answer: 1)
    patch user_schedule_path(@circle, @event), params: { schedule: { recruitment_numbers: 1 } }
    assert_response :success
    assert_equal 10, @event.reload.recruitment_numbers
  end

  test 'deletion requires a separate review page and removes only this event and its answers' do
    sign_in
    assert_no_difference ['Schedule.count', 'NameSchedule.count'] do
      get confirm_delete_user_schedule_path(@circle, @event)
    end
    assert_response :success
    assert_select '.em-note--danger', text: /出欠回答も削除/
    assert_select "form[action='#{user_schedule_path(@circle, @event)}'] input[name=_method][value=delete]"
    assert_difference 'Schedule.count', -1 do
      assert_difference 'NameSchedule.count', -2 do
        delete user_schedule_path(@circle, @event)
      end
    end
    assert_redirected_to user_schedules_path(@circle)
    assert Schedule.exists?(@next.id)
    assert Name.exists?(@yes.id)
  end

  test 'owner cards paginate without loading participant rows or one count query per event' do
    23.times { |i| @circle.schedules.create!(day: '2026-11-14', title: "追加の練習#{i}", venue: '川崎市') }
    sign_in
    instantiated = Hash.new(0)
    queries = []
    ActiveSupport::Notifications.subscribed(->(*args) { p = args.last; instantiated[p[:class_name]] += p[:record_count] }, 'instantiation.active_record') do
      ActiveSupport::Notifications.subscribed(->(*args) { p = args.last; queries << p[:sql] unless p[:cached] || p[:name] == 'SCHEMA' }, 'sql.active_record') do
        get user_schedules_path(@circle)
      end
    end
    assert_response :success
    assert_select '.em-event', count: 20
    assert_equal 0, instantiated['NameSchedule']
    assert_equal 1, queries.count { |sql| sql.include?('GROUP BY "name_schedules"."schedule_id", "name_schedules"."answer"') }
    get user_schedules_path(@circle), params: { page: 2 }
    assert_select '.em-event', count: 5
  end
end
