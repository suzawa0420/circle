require 'minitest/autorun'
require_relative '../../app/helpers/users_helper'

class CircleLevelStatusTest < Minitest::Test
  include UsersHelper
  Score = Struct.new(:cb_point)

  def test_tenths_and_float_rounding
    { 0 => [0, 0, 1.0], 0.9 => [0, 90, 0.1], 1.0 => [1, 0, 1.0],
      64.1 => [64, 10, 0.9], 64.99999999999999 => [65, 0, 1.0],
      99.9 => [99, 90, 0.1] }.each do |points, expected|
      status = circle_level_status(Score.new(points))
      assert_equal expected, status.values_at(:level, :progress, :remaining)
      refute status[:maximum]
    end
  end

  def test_cap_and_negative_scores
    [100, 100.1, 1000].each do |points|
      assert_equal({ level: 100, maximum: true, progress: 100, remaining: 0.0 }, circle_level_status(Score.new(points)))
    end
    assert_equal 0, circle_level_status(Score.new(-30))[:level]
  end

  def test_deletion_can_lower_a_maximum_level
    score = Score.new(100.1)
    assert circle_level_status(score)[:maximum]
    score.cb_point -= 0.2
    assert_equal 99, circle_level_status(score)[:level]
    assert_equal 90, circle_level_status(score)[:progress]
  end
end
