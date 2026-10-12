require 'minitest/autorun'
require 'action_view'
require 'haml'
require 'haml/rails_template'
require_relative '../../app/helpers/reviews_helper'
require_relative '../../app/helpers/lucide_helper'

class ReviewsHelperTest < Minitest::Test
  include ReviewsHelper

  def test_unrated_and_zero_rated_are_distinct
    assert_equal 0, review_star_score(0, reviews_count: 0)
    assert_equal 0.5, review_star_score(0, reviews_count: 1)
  end

  def test_half_star_boundaries_and_caps
    { -1 => 0.5, 0.01 => 0.5, 0.4 => 0.5, 0.5 => 0.5,
      0.5001 => 1, 1 => 1, 1.001 => 1.5, 1.5 => 1.5,
      2.5 => 2.5, 3.5 => 3.5, 4.5 => 4.5, 4.501 => 5,
      5 => 5, 6 => 5 }.each do |score, expected|
      assert_equal expected, review_star_score(score, reviews_count: 1), "score=#{score}"
    end
  end

  def test_rendered_stars_and_actual_score
    view = ActionView::Base.with_empty_template_cache.with_view_paths(File.expand_path('../../app/views', __dir__))
    view.extend ReviewsHelper
    view.extend LucideHelper
    [[0, 0, 0], [0, 1, 1], [0.5, 1, 1], [0.51, 1, 0], [4.5, 1, 1], [5, 1, 0]].each do |score, count, halves|
      html = view.render(partial: 'layouts/review_score', locals: { review_score: score, reviews_count: count })
      doc = Nokogiri::HTML.fragment(html)
      assert_equal halves, doc.css('.review-half-star').size
      assert_equal review_star_score(score, reviews_count: count).ceil, doc.css('.orange').size
      assert_equal format('%.2f', score), doc.at_css('.review_score').text
      assert_equal 5 + halves, doc.css('.star svg').size
    end
    html = view.render(partial: 'place_reviews/review_score', locals: { review_score: 0 })
    assert_equal 1, Nokogiri::HTML.fragment(html).css('.review-half-star').size
  end
end
