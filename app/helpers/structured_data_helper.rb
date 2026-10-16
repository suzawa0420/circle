module StructuredDataHelper
  # Both facility ratings and circle recommendation averages use a 0–5 scale.
  # Do not invent a zero rating for missing aggregates or clamp invalid values.
  def review_aggregate_rating(score, review_count:)
    rating = Float(score, exception: false)
    return unless review_count.positive? && rating&.finite? && rating.between?(0, 5)

    {
      '@type' => 'AggregateRating',
      'ratingValue' => rating,
      'worstRating' => 0,
      'bestRating' => 5,
      'reviewCount' => review_count
    }
  end
end
