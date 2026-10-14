module PlacesHelper
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
