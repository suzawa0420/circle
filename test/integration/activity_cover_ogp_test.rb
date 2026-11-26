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
    get '/images/ogp/events/basketball.jpg'
    assert_response :success
    assert_equal 'image/jpeg', response.media_type
    assert_equal [1200, 630], MiniMagick::Image.read(response.body).dimensions
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
end
