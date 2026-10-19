require 'minitest/autorun'
require 'active_support/all'
require 'action_view'
require 'mini_magick'
require 'ostruct'
require 'nokogiri'
require_relative '../../app/helpers/lucide_helper'
require_relative '../../app/services/schedule_ogp_image'

class ScheduleOgpImageTest < Minitest::Test
  def setup
    @schedule = OpenStruct.new(title: '初心者歓迎！新宿でボードゲーム＆お菓子交流会',
      venue: '東京都新宿区', day: '2026-10-25', time_s: Time.parse('16:30'), time_e: Time.parse('18:00'))
    # Any attempt to use member-only information must fail, even for a fallback.
    %i[member_venue venue_address google_map].each do |attribute|
      @schedule.define_singleton_method(attribute) { raise 'Private field must not be used' }
    end
    @image = ScheduleOgpImage.new(@schedule)
  end

  def test_long_title_has_at_most_three_lines_and_venue_is_one_line
    @schedule.title = 'とても長いイベントタイトル' * 30
    @schedule.venue = "東京都新宿区\n" + '一般公開の活動エリア' * 30
    assert_equal 3, @image.title_lines.length
    assert @image.title_lines.last.end_with?('…')
    assert @image.venue_line.end_with?('…')
    refute_match(/[\r\n]/, @image.venue_line)
    assert_operator @image.venue_line.length, :<=, 16
  end

  def test_calendar_and_time_use_event_values_and_handle_missing_times
    assert_equal '2026年10月25日（日）', @image.date_label
    assert_equal '16:30〜18:00', @image.time_label
    @schedule.time_e = nil
    assert_equal '16:30〜', @image.time_label
    @schedule.time_s = nil
    assert_equal '時間未定', @image.time_label
    @schedule.day = 'invalid'
    assert_equal '日程未定', @image.date_label
  end

  def test_svg_escapes_user_text_and_contains_only_the_public_venue
    @schedule.title = '<b>初心者歓迎</b> & 交流会'
    @schedule.venue = '東京都新宿区'
    xml = Nokogiri::XML(@image.send(:layout_svg)) { |config| config.strict }
    texts = xml.xpath('//*[local-name()="text"]').map(&:text)
    assert_includes texts, '初心者歓迎 & 交流会'
    assert_includes texts, '東京都新宿区'
    assert_equal 1, texts.count('東京都新宿区')
    assert_empty xml.xpath('//*[local-name()="b"]')
    @schedule.venue = ''
    assert_equal '', @image.venue_line
  end

  def test_real_renderer_returns_a_1200_by_630_png
    source = File.expand_path('../../public/images/events/event.jpg', __dir__)
    @image.define_singleton_method(:square_photo) do
      image = MiniMagick::Image.open(source)
      image.combine_options { |cmd| cmd.resize '480x480^'; cmd.gravity 'center'; cmd.extent '480x480' }
      image.format 'png'
      image
    end
    png = @image.send(:render)
    assert png.start_with?("\x89PNG\r\n\x1a\n".b)
    rendered = MiniMagick::Image.read(png)
    assert_equal [1200, 630], rendered.dimensions
  ensure
    rendered&.destroy!
  end
end
