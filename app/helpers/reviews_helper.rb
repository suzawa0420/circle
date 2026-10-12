module ReviewsHelper
  # Keep the actual score unchanged; rated profiles always show at least half a star.
  def review_star_score(score, reviews_count:)
    return 0.0 unless reviews_count.to_i.positive?

    [(score.to_f.clamp(0, 5) * 2).ceil / 2.0, 0.5].max
  end
end
