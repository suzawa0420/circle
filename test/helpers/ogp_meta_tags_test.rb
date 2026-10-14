require 'minitest/autorun'
require 'action_view'
require 'action_controller'
require 'meta_tags'
require 'nokogiri'
require_relative '../../app/helpers/application_helper'
require_relative '../../app/decorators/user_decorator'
require_relative '../../app/decorators/blog_decorator'
require_relative '../../app/decorators/schedule_decorator'

class OgpMetaTagsTest < Minitest::Test
  Upload = Struct.new(:url)

  def setup
    @view = ActionView::Base.empty
    @view.extend ApplicationHelper
    @view.extend MetaTags::ViewHelper
    def @view.image_url(path)
      "https://circle-book.com#{path}"
    end
    def @view.request
      Struct.new(:original_url).new('https://circle-book.com/example')
    end
  end

  def rendered_image
    Nokogiri::HTML.fragment(@view.site_meta_tags).at_css('meta[property="og:image"]')['content']
  end

  def test_missing_and_blank_page_images_use_the_default
    assert_equal @view.default_ogp_image_url, rendered_image
    [nil, '', '  ', []].each do |image|
      @view.set_meta_tags og: { image: image, title: 'ページ固有のタイトル' }
      html = Nokogiri::HTML.fragment(@view.site_meta_tags)
      assert_equal @view.default_ogp_image_url, html.at_css('meta[property="og:image"]')['content']
      assert_equal 'ページ固有のタイトル', html.at_css('meta[property="og:title"]')['content']
    end
  end

  def test_custom_image_is_preserved
    @view.set_meta_tags og: { image: 'https://example.com/custom.jpg' }
    assert_equal 'https://example.com/custom.jpg', rendered_image
  end

  def decorated_record(decorator, attributes)
    record = Object.new.extend(decorator)
    attributes.each { |key, value| record.define_singleton_method(key) { value } }
    default = @view.default_ogp_image_url
    record.define_singleton_method(:default_ogp_image_url) { default }
    record
  end

  def test_circle_image_priority_and_missing_image_fallback
    profile, header = Upload.new('profile.jpg'), Upload.new('header.jpg')
    record = decorated_record(UserDecorator, pic_profile: profile, pic_header: header)
    assert_equal 'profile.jpg', record.ogp_img
    record.define_singleton_method(:pic_profile) { nil }
    assert_equal 'header.jpg', record.ogp_img
    record.define_singleton_method(:pic_header) { nil }
    assert_equal @view.default_ogp_image_url, record.ogp_img
  end

  def test_blog_and_schedule_without_images_use_the_default
    circle = Struct.new(:pic_profile, :pic_header).new(nil, nil)
    blog = decorated_record(BlogDecorator, image_01: nil, user: circle)
    schedule = decorated_record(ScheduleDecorator, top_image: nil)
    assert_equal @view.default_ogp_image_url, blog.ogp_img
    assert_equal @view.default_ogp_image_url, schedule.ogp_img
    blog.define_singleton_method(:image_01) { Upload.new('blog.jpg') }
    schedule.define_singleton_method(:top_image) { Upload.new('event.jpg') }
    assert_equal 'blog.jpg', blog.ogp_img
    assert_equal 'event.jpg', schedule.ogp_img
  end
end
