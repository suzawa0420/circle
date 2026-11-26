require 'test_helper'
require_relative '../support/chat_records'

class ActivityCoverOgpTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    @circle.event.update!(ruby: 'basketball')
  end

  test 'sport list circle and blog have distinct display and social covers' do
    blog = @circle.blogs.create!(title: '練習会の記録', content: '練習会に参加した感想を掲載しています。' * 8)
    [event_path('basketball'), circle_path(@circle), circle_blog_path(@circle, blog)].each do |path|
      get path
      assert_response :success
      assert_select 'img[src="/images/events/basketball.jpg"]'
      assert_select 'meta[property="og:image"][content$="/images/ogp/events/basketball.jpg"]', count: 1
      assert_select 'img[src="/images/ogp/events/basketball.jpg"]', count: 0
    end
    assert_jpeg_dimensions '/images/events/basketball.jpg', [1000, 500]
    assert_jpeg_dimensions '/images/ogp/events/basketball.jpg', [1200, 630]
  end

  test 'category has separate display and social covers' do
    @circle.event.category.update!(kana: 'ball-sports')
    get '/categories/ball-sports'
    assert_response :success
    assert_select 'img[src="/images/categories/ball-sports.jpg"]'
    assert_select 'meta[property="og:image"][content$="/images/ogp/categories/ball-sports.jpg"]', count: 1
    assert_jpeg_dimensions '/images/categories/ball-sports.jpg', [1000, 500]
    assert_jpeg_dimensions '/images/ogp/categories/ball-sports.jpg', [1200, 630]
  end

  test 'schedule preview uses the corresponding OGP fallback as its square photo' do
    schedule = @circle.schedules.create!(day: '2026-12-12', title: 'バスケットボール交流会', venue: '世田谷区')
    ogp = ScheduleOgpImage.new(schedule)
    assert_equal Rails.root.join('public/images/ogp/events/basketball.jpg').to_s, ogp.send(:fallback_photo)
    get ogp_user_schedule_path(@circle, schedule, format: :png)
    assert_response :success
    assert_equal 'image/png', response.media_type
    rendered = MiniMagick::Image.read(response.body)
    assert_equal [1200, 630], rendered.dimensions
    @circle.event.category.update!(kana: 'ball-sports')
    @circle.event.update!(ruby: 'no-local-photo')
    assert_equal Rails.root.join('public/images/ogp/categories/ball-sports.jpg').to_s, ogp.send(:fallback_photo)
  ensure
    rendered&.destroy!
  end

  test 'uploaded covers still take precedence in social previews' do
    File.open(Rails.root.join('public/images/events/basketball.jpg')) do |file|
      @circle.update!(pic_header: file)
    end
    get circle_path(@circle)
    assert_response :success
    assert_select 'meta[property="og:image"][content=?]', @circle.pic_header.url, count: 1
  ensure
    @circle.pic_header.remove! if @circle.pic_header.present?
  end

  private

  def assert_jpeg_dimensions(path, dimensions)
    get path
    assert_response :success
    assert_equal 'image/jpeg', response.media_type
    image = MiniMagick::Image.read(response.body)
    assert_equal dimensions, image.dimensions
  ensure
    image&.destroy!
  end
end
