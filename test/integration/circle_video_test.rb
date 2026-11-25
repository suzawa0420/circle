require 'test_helper'
require_relative '../support/chat_records'

class CircleVideoTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup { create_chat_records }

  test 'owner can save a video and remove it from their circle' do
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    get edit_user_path(@circle)
    assert_select 'input[type=url][name="user[youtube_url]"]'
    patch user_path(@circle), params: { user: { youtube_url: 'https://youtu.be/Abcde_123-4' } }
    assert_response :redirect
    assert_equal 'https://youtu.be/Abcde_123-4', @circle.reload.youtube_url

    get circle_path(@circle)
    assert_response :success
    assert_select '.cb-detail-media[data-circle-gallery] #circle-gallery-dialog', count: 1
    assert_select '[data-circle-gallery-open][data-circle-gallery-kind="video"] img[src="https://i.ytimg.com/vi/Abcde_123-4/hqdefault.jpg"]'
    assert_select '[data-circle-gallery-open][data-circle-gallery-video-id="Abcde_123-4"][href="https://www.youtube.com/watch?v=Abcde_123-4"]'
    assert_select '#circle-gallery-dialog [data-circle-gallery-move]', count: 0
    assert_select '#circle-gallery-dialog iframe', count: 0

    patch user_path(@circle), params: { user: { youtube_url: '' } }
    assert_response :redirect
    assert_equal '', @circle.reload.youtube_url
    get circle_path(@circle)
    assert_select '.cb-detail-media', count: 0
  end

  test 'invalid video URL shows an error and preserves saved data' do
    @circle.update!(youtube_url: 'https://youtu.be/Abcde_123-4')
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    [
      'https://example.test/video',
      'https://vimeo.com/123456789',
      'https://www.tiktok.com/@circle/video/123456789',
      'https://youtube.com.evil.test/watch?v=Abcde_123-4',
      'https://youtube.com@evil.test/watch?v=Abcde_123-4',
      'javascript:alert(1)',
      'https://www.youtube.com/@circle'
    ].each do |url|
      patch user_path(@circle), params: { user: { youtube_url: url } }
      assert_response :unprocessable_entity
      assert_select '.form-error_message', text: /YouTubeの動画URL/
      assert_equal 'https://youtu.be/Abcde_123-4', @circle.reload.youtube_url
    end
  end

  test 'normal URLs and Shorts are accepted but overly long URLs are rejected' do
    ['https://www.youtube.com/watch?v=Abcde_123-4', 'https://www.youtube.com/shorts/Abcde_123-4'].each do |url|
      @circle.update!(youtube_url: url)
      assert_equal 'Abcde_123-4', @circle.reload.youtube_video_id
    end
    @circle.youtube_url = 'https://youtu.be/Abcde_123-4?si=' + 'x' * 255
    refute @circle.valid?
    assert @circle.errors.of_kind?(:youtube_url, :too_long)
    @circle.youtube_url = nil
    assert @circle.valid?
  end

  test 'only the circle owner can change a video' do
    other = AdminUser.create!(email: 'other-video-owner@example.test', password: 'test-password-123')
    post admin_user_session_path, params: { admin_user: { email: other.email, password: 'test-password-123' } }
    patch user_path(@circle), params: { user: { youtube_url: 'https://youtu.be/Abcde_123-4' } }
    assert_response :redirect
    assert_nil @circle.reload.youtube_url
  end

  test 'a circle without a video has no preview or player' do
    get circle_path(@circle)
    assert_response :success
    assert_select '.cb-detail-media', count: 0
  end

  test 'gallery combines photos and video without another popup or a text close button' do
    photos = { gallery_01: 'gallery-proof-one.jpg', gallery_03: 'gallery-proof-three.jpg' }
    @circle.update_columns(photos.merge(youtube_url: 'https://youtu.be/Abcde_123-4'))
    stored_paths = photos.map do |mount, filename|
      uploader = @circle.public_send(mount)
      File.join(uploader.root, uploader.store_path(filename))
    end
    stored_paths.each do |path|
      FileUtils.mkdir_p(File.dirname(path))
      FileUtils.cp(Rails.root.join('public/images/listing-default-header-v1.jpg'), path)
    end

    get circle_path(@circle)
    assert_response :success

    assert_select '.cb-detail-media[data-circle-gallery]' do
      assert_select '[data-circle-gallery-open]', count: 3
      assert_select '[data-circle-gallery-kind="image"]', count: 2
      assert_select '[data-circle-gallery-kind="video"]', count: 1
      assert_select 'dialog#circle-gallery-dialog', count: 1 do
        assert_select 'button[data-circle-gallery-move="-1"][aria-label="前の写真・動画"]', count: 1
        assert_select 'button[data-circle-gallery-move="1"][aria-label="次の写真・動画"]', count: 1
        assert_select 'button[data-circle-gallery-close][aria-label="閉じる"]', count: 1, text: ''
        assert_select '[data-circle-gallery-status][aria-live="polite"]', count: 1
        assert_select 'a[data-circle-gallery-fallback][hidden]', count: 1
        assert_select 'iframe', count: 0
      end
      assert_select '.popup, input[type="checkbox"]', count: 0
    end
  ensure
    FileUtils.rm_f(stored_paths || [])
  end

  test 'public detail stylesheet retains the gallery preview and dialog styles' do
    css = Rails.application.assets.find_asset('public_detail.css').to_s
    %w[.cb-circle-gallery__thumbnails .cb-circle-gallery__play .cb-circle-gallery__dialog .cb-circle-gallery__media .cb-circle-gallery__control .cb-circle-gallery__next].each do |selector|
      assert_includes css, selector
    end
  end
end
