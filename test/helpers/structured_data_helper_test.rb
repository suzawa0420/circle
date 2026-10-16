require 'test_helper'

class StructuredDataHelperTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  include StructuredDataHelper

  test 'only finite scores on the published scale with actual reviews produce ratings' do
    [nil, '', 'unknown', -0.1, 5.1, Float::NAN, Float::INFINITY].each do |score|
      assert_nil review_aggregate_rating(score, review_count: 1)
    end
    assert_nil review_aggregate_rating(5, review_count: 0)
    assert_nil review_aggregate_rating(5, review_count: -1)
    assert_equal 0.5, review_aggregate_rating('0.5', review_count: 2)['ratingValue']
    assert_equal 0, review_aggregate_rating(0, review_count: 1)['worstRating']
    assert_equal 5, review_aggregate_rating(5, review_count: 1)['bestRating']
  end
end
