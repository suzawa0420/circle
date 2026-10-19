require 'test_helper'
require_relative '../support/chat_records'

class ScheduleOgpImagesTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    @schedule = @circle.schedules.create!(day: '2026-10-25',
      title: '初心者歓迎！新宿でボードゲーム＆お菓子交流会', venue: '東京都新宿区',
      time_s: '16:30', time_e: '18:00', member_venue: 'メンバーだけの体育館',
      venue_address: 'メンバーだけの詳細住所', google_map: '非公開の地図URL')
  end

  test 'public detail uses an absolute versioned PNG for both Open Graph and Twitter' do
    get user_schedule_path(@circle, @schedule)
    assert_response :success
    image = css_select('meta[property="og:image"]').first['content']
    assert_match %r{\Ahttp://www.example.com/users/#{@circle.id}/schedules/#{@schedule.id}/ogp.png\?v=[0-9a-f]{24}\z}, image
    assert_select 'meta[property="og:image:width"][content="1200"]'
    assert_select 'meta[property="og:image:height"][content="630"]'
    assert_select 'meta[name="twitter:image"][content=?]', image
    @schedule.update!(title: '更新されたイベントタイトル')
    get user_schedule_path(@circle, @schedule)
    assert_not_equal image, css_select('meta[property="og:image"]').first['content']
  end

  test 'anonymous image requests return PNG without reading private venue columns' do
    image = ScheduleOgpImage.new(@schedule)
    png = image.png
    assert_equal '東京都新宿区', image.venue_line
    selected_private_columns = []
    callback = lambda do |*args|
      sql = args.last[:sql]
      selected_private_columns << sql if sql.match?(/SELECT.*(?:member_venue|venue_address|google_map)/i)
    end
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      get ogp_user_schedule_path(@circle, @schedule, format: :png)
    end
    assert_response :success
    assert_equal 'image/png', response.media_type
    assert_equal png, response.body.b
    assert_empty selected_private_columns
    assert_includes response.headers['Cache-Control'], 'public'
    assert_equal 'nosniff', response.headers['X-Content-Type-Options']
    etag = response.headers['ETag']
    get ogp_user_schedule_path(@circle, @schedule, format: :png), headers: { 'If-None-Match' => etag }
    assert_response :not_modified
  end

  test 'wrong circle missing records and hidden circles cannot generate images' do
    get ogp_user_schedule_path(@circle.id + 100000, @schedule, format: :png)
    assert_response :not_found
    get ogp_user_schedule_path(@circle, @schedule.id + 100000, format: :png)
    assert_response :not_found
    @circle.update_columns(moderation_status: 'held')
    get ogp_user_schedule_path(@circle, @schedule, format: :png)
    assert_response :not_found
  end

  test 'uploaded event photo is used and changed uploads invalidate the cache version' do
    original = ScheduleOgpImage.version_for(@schedule)
    File.open(Rails.root.join('public/images/events/event.jpg')) do |file|
      @schedule.top_image = file
      @schedule.save!
    end
    assert_not_equal original, ScheduleOgpImage.version_for(@schedule)
    png = ScheduleOgpImage.new(@schedule).png
    rendered = MiniMagick::Image.read(png)
    assert_equal [1200, 630], rendered.dimensions
  ensure
    rendered&.destroy!
    @schedule.top_image.remove!
  end
end
