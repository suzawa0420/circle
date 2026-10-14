module CircleSearchFiltersHelper
  # Canonical path dimensions and explicit filters share a single GET form.
  # Only recognized filters survive removal; page resets when results change.
  def circle_search_filters
    @circle_search_filters ||= begin
      source = @landing_filters || params
      filters = { detailed: '1' }
      %i[q sort event_id prefecture_id category_id city_id tag_id].each do |key|
        filters[key] = source[key].to_s if source[key].present?
      end
      filters[:sort] = params[:sort].to_s if params[:sort].present?
      { event_id: @event, prefecture_id: @prefecture, category_id: @category, city_id: @city, tag_id: @tag }.each do |key, record|
        filters[key] ||= record.id.to_s if record
      end
      %i[group_ids age_ids].each do |key|
        values = Array(source[key]).map(&:to_s).reject(&:blank?).uniq
        filters[key] = values if values.any?
      end
      filters
    end
  end

  def circle_active_filters
    @circle_active_filters ||= begin
      filters = circle_search_filters
      items = []
      filters[:q].to_s.split(/[[:blank:]]+/).uniq.each do |word|
        remaining = filters[:q].split(/[[:blank:]]+/).reject { |value| value == word }.join(' ')
        items << { key: :q, label: "「#{word}」", url: circles_search_index_path(filters.merge(q: remaining)) }
      end
      { event_id: @event, prefecture_id: @prefecture, category_id: @category, city_id: @city, tag_id: @tag }.each do |key, record|
        items << { key: key, label: record.name, url: circles_search_index_path(filters.except(key)) } if record && filters[key]
      end
      { group_ids: @search_groups, age_ids: @search_ages }.each do |key, records|
        Array(records).each do |record|
          remaining = Array(filters[key]) - [record.id.to_s]
          items << { key: key, label: record.name, url: circles_search_index_path(filters.merge(key => remaining)) }
        end
      end
      items
    end
  end

  def circle_search_relaxations
    # Choices within each dimension use OR. Removing one of several choices
    # would narrow results, so empty-state recovery removes the whole dimension.
    items = circle_active_filters.reject { |item| %i[group_ids age_ids].include?(item[:key]) }
    { group_ids: '募集内容', age_ids: '年齢層' }.each do |key, label|
      if circle_search_filters[key].present?
        items << { label: label, url: circles_search_index_path(circle_search_filters.except(key)) }
      end
    end
    items
  end

end
