module PlacesHelper
  def place_listing_structured_data(places)
    entries = places.map do |place|
      { 'url' => "https://circle-book.com#{place_listing_path(place)}", 'name' => place.name.to_s }
    end
    structured_collection(entries, offset: places.respond_to?(:offset_value) ? places.offset_value : 0)
  end

  def facility_structured_data(place)
    return unless public_structured_data_page?
    data = {
      '@context' => 'https://schema.org', '@type' => 'LocalBusiness',
      'additionalType' => 'https://schema.org/SportsActivityLocation',
      '@id' => "https://circle-book.com/places#facility-#{place.id}", 'url' => structured_page_url,
      'name' => place.name.to_s,
      'description' => "#{place.prefecture.name}#{place.city.name}にある#{place.name}のコート情報",
      'mainEntityOfPage' => { '@type' => 'WebPage', '@id' => structured_page_url },
      'address' => { '@type' => 'PostalAddress', 'addressCountry' => 'JP',
        'addressRegion' => place.prefecture.name.to_s, 'addressLocality' => place.city.name.to_s,
        'streetAddress' => place.address.to_s }
    }
    data['telephone'] = place.tel if place.tel.present?
    data['priceRange'] = place.price if place.price.present?
    if place.url.to_s.match?(%r{\Ahttps?://}i) && (official = structured_absolute_url(place.url))
      data['sameAs'] = official
    end
    rating = review_aggregate_rating(place.average_score, review_count: place.public_place_reviews.count)
    data['aggregateRating'] = rating if rating
    data
  end

  def place_listing_path(place)
    event = @event || place.events.find { |candidate| candidate.place == 1 } || place.events.first
    sport = event&.ruby.presence || "all"
    "/places/#{sport}/#{place.prefecture.kana}/#{place.city.city_kana}/#{place.id}"
  end

  def place_summary(value, length: 90)
    text = strip_tags(value.to_s).squish
    text.present? ? truncate(text, length: length) : "記載なし"
  end

  def place_detail_text(value)
    return content_tag(:p, "記載なし", class: "place-detail-muted") if value.blank?

    sanitize(Rinku.auto_link(simple_format(value.to_s)), tags: %w[p br a], attributes: %w[href])
  end

  def place_search_keyword
    params[:kw].is_a?(String) ? params[:kw] : ''
  end
end
