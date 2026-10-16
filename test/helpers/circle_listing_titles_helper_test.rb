require 'minitest/autorun'
require 'action_view'
require 'action_controller'
require 'nokogiri'
require_relative '../../app/helpers/circle_listing_titles_helper'

class CircleListingTitlesHelperTest < Minitest::Test
  Named = Struct.new(:name)
  Activity = Struct.new(:name, :txt)

  def setup
    @view = ActionView::Base.empty
    @view.extend CircleListingTitlesHelper
    @view.instance_variable_set(:@users, Struct.new(:total_count, :current_page).new(1013, 1))
    @view.instance_variable_set(:@prefecture, Named.new('東京都'))
    @view.instance_variable_set(:@city, Named.new('渋谷区'))
    def @view.controller_path; 'circles/search'; end
    def @view.params; { detailed: '1' }.with_indifferent_access; end
  end

  def heading
    Nokogiri::HTML.fragment(@view.circle_listing_heading)
  end

  def test_city_and_count_share_intro_and_activity_has_its_own_line
    html = heading
    assert_equal '全1,013件東京都渋谷区の', html.at_css('.circle-listing-heading__intro').text
    assert_equal 'サークル・チーム募集', html.at_css('.circle-listing-heading__subject').text
    assert_nil html.at_css('.circle-listing-heading__conditions')
    assert_equal '【全1,013件】東京都渋谷区のサークル・チーム募集', @view.circle_listing_title
  end

  def test_audience_is_grouped_separately_without_losing_search_terms
    @view.instance_variable_set(:@search_groups, [Named.new('経験者')])
    @view.instance_variable_set(:@search_ages, [Named.new('20代')])
    @view.instance_variable_set(:@event, Activity.new('バドミントン', 'バドミントンサークル・クラブ'))
    html = heading
    assert_equal '経験者／20代向けの', html.at_css('.circle-listing-heading__conditions').text
    assert_equal 'バドミントンサークル募集', html.at_css('.circle-listing-heading__subject').text
    assert_equal @view.circle_listing_title.delete_prefix('【').sub('】', ''), html.text
  end

  def test_long_filters_keep_full_text_and_metadata
    @view.instance_variable_set(:@search_groups, %w[初心者 経験者 学生 社会人 男子 女子 男女].map { |name| Named.new(name) })
    @view.instance_variable_set(:@search_ages, %w[10代 20代 30代 40代 50代 60代以上].map { |name| Named.new(name) })
    condition = heading.at_css('.circle-listing-heading__conditions')
    assert_equal condition.text, condition['title']
    assert_includes condition.text, '60代以上'
    assert_includes @view.circle_listing_title, condition.text
  end

  def test_keyword_is_escaped_and_preserved
    def @view.params; { detailed: '1', q: '<script>alert(1)</script>' }.with_indifferent_access; end
    html = heading
    assert_empty html.css('script')
    assert_includes html.text, '<script>alert(1)</script>'
  end
end
