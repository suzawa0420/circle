require 'test_helper'
require_relative '../support/chat_records'

class ScheduleDetailDesignTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    travel_to Time.zone.local(2026, 10, 13, 12)
    create_chat_records
    @circle.update!(recruitment: '初心者歓迎', unique_id: 'schedule-detail-test')
    @circle.event.update!(ruby: 'basketball')
    @schedule = @circle.schedules.create!(day: '2026-10-13', title: '駒込・田端（文京区）でバスケ',
      venue: '駒込／田端', time_s: '18:30', time_e: '21:30', cost: '男性1,500円／女性1,000円',
      member_venue: '非公開体育館', venue_address: '非公開住所', recruitment_numbers: 10,
      note: '<div>シューズを持参してください。<script>alert(1)</script><a href="javascript:alert(1)">危険なリンク</a></div>')
  end

  teardown { travel_back }

  test 'title image and essential facts share one card with the original inquiry link' do
    get user_schedule_path(@circle, @schedule)
    assert_response :success
    assert_select '.schedule-detail__title', text: @schedule.title
    assert_select '.schedule-detail__card > .schedule-detail__heading + .schedule-detail__image + .schedule-detail__summary', count: 1
    assert_select '.schedule-detail__image img[src="/images/events/basketball.jpg"][fetchpriority="high"]'
    assert_select '.schedule-detail__facts', text: /18:30–21:30.*駒込／田端.*男性1,500円／女性1,000円/m
    assert_select '.schedule-detail__contact[href=?][data-circle-inquiry-click]', new_user_conversation_path(@circle)
    assert_select '.schedule-detail__organizer[href=?]', circle_path(@circle)
    assert_select '.schedule-detail__body', text: /シューズを持参/
    assert_select '.schedule-detail__body script', count: 0
    assert_select '.schedule-detail__body a[href^="javascript:"]', count: 0
    assert_not_includes response.body, '非公開体育館'
    assert_not_includes response.body, '非公開住所'
    assert_select '.schedule-detail__management', count: 0
  end

  test 'uploaded announcement image is used intact instead of the common sport image' do
    File.open(Rails.root.join('public/images/events/basketball.jpg')) do |file|
      @schedule.top_image = file
      @schedule.save!
    end
    get user_schedule_path(@circle, @schedule)
    assert_response :success
    assert_select '.schedule-detail__image img[src=?]', @schedule.top_image.url
    assert_select '.schedule-detail__image img[src="/images/events/basketball.jpg"]', count: 0
  ensure
    @schedule.top_image.remove!
  end

  test 'availability respects Japanese clock times and does not load participant records' do
    NameSchedule.insert_all!([{ schedule_id: @schedule.id, answer: 1, created_at: Time.current, updated_at: Time.current }])
    @schedule.update!(recruitment_numbers: 1)
    records = Hash.new(0)
    ActiveSupport::Notifications.subscribed(->(*args) { p = args.last; records[p[:class_name]] += p[:record_count] }, 'instantiation.active_record') do
      get user_schedule_path(@circle, @schedule)
    end
    assert_select '.schedule-detail__status.status-full', text: '満員'
    assert_equal 0, records['NameSchedule']
    @schedule.update!(recruitment_numbers: 3)
    get user_schedule_path(@circle, @schedule)
    assert_select '.schedule-detail__status.status-few', text: '残りわずか'
    travel_to Time.zone.local(2026, 10, 13, 22)
    get user_schedule_path(@circle, @schedule)
    assert_select '.schedule-detail__status.status-ended', text: '開催終了'
    @schedule.update!(recruitment: '中止')
    get user_schedule_path(@circle, @schedule)
    assert_select '.schedule-detail__status.status-cancelled', text: '中止'
  end

  test 'owner operations remain available and limited detail keeps private venue information' do
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    get user_schedule_path(@circle, @schedule)
    assert_select '.schedule-detail__management a[href=?]', edit_user_schedule_path(@circle, @schedule)
    assert_select '.schedule-detail__management a[href=?]', new_user_schedule_path(@circle, copy: @schedule.id, copy_mode: :next_week)
    get "/schedules/#{@circle.unique_id}/#{@schedule.id}"
    assert_response :success
    assert_select '.secret_schedule', count: 1
    assert_includes response.body, '非公開体育館'
    assert_includes response.body, '非公開住所'
  end
end
