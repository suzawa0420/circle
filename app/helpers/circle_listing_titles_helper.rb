module CircleListingTitlesHelper
  # Use the same filtered, paginated relation as the list. total_count removes
  # pagination, retains visibility/area/tag predicates, and uses the list cache.
  def circle_listing_title
    @circle_listing_title ||= begin
      count = number_with_delimiter(@users.total_count)
      page = @users.current_page > 1 ? "（#{@users.current_page}ページ目）" : ''
      "【全#{count}件】#{circle_listing_subject}#{page}"
    end
  end

  def circle_listing_heading
    count, _bracket, subject = circle_listing_title.partition('】')
    area = [@prefecture&.name, @city&.name].compact.join
    area = area.present? && subject.start_with?("#{area}の") ? "#{area}の" : nil
    subject = subject.delete_prefix(area) if area

    conditions = []
    if controller_path == 'circles/search' && (@filtered_landing || params[:detailed] == '1')
      audience = [Array(@search_groups).map(&:name).join('・').presence,
                  Array(@search_ages).map(&:name).join('・').presence].compact.join('／')
      conditions << "#{audience}向けの" if audience.present?
    end
    conditions << (@tag.text.presence || "#{@tag.name}の") if @tag
    condition = conditions.join
    if condition.present? && subject.start_with?(condition)
      subject = subject.delete_prefix(condition)
    else
      condition = nil
    end

    # Keep established wording and the complete accessible text. Only the visual
    # grouping changes; long filters are also listed in full below the form.
    safe_join([
      content_tag(:span, class: 'circle-listing-heading__intro') do
        safe_join([
          content_tag(:span, count.delete_prefix('【'), class: 'circle-listing-heading__count'),
          (content_tag(:span, area, class: ['circle-listing-heading__area', ('circle-listing-heading__area--long' if area.length > 9)]) if area)
        ].compact)
      end,
      (content_tag(:span, condition, class: 'circle-listing-heading__conditions', title: condition) if condition),
      content_tag(:span, subject, class: ['circle-listing-heading__subject', ('circle-listing-heading__subject--long' if subject.length > 14)], title: subject)
    ])
  end

  def circle_listing_subject
    if controller_path == 'circles/search'
      return detailed_circle_listing_subject if @filtered_landing || params[:detailed] == "1"
      return "「#{params[:q]}」のサークル・チーム検索結果"
    end

    area = [@prefecture&.name, @city&.name].compact.join
    area = area.present? ? "#{area}の" : ''
    activity = @event&.txt.presence || (@event && "#{@event.name}サークル") ||
      @category&.txt.presence || (@category && "#{@category.name}のサークル・チーム") || 'サークル・チーム'
    # Keep each genre's established wording (teams, choirs, student groups, etc.).
    activity = activity.sub(/サークル・クラブ\z/, 'サークル')
    condition = @tag && (@tag.text.presence || "#{@tag.name}の")
    "#{area}#{condition}#{activity}募集"
  end

  def detailed_circle_listing_subject
    area = [@prefecture&.name, @city&.name].compact.join
    activity = @event&.txt.presence || (@event && "#{@event.name}サークル") ||
      @category&.txt.presence || (@category && "#{@category.name}のサークル・チーム") || 'サークル・チーム'
    activity = activity.sub(/サークル・クラブ\z/, 'サークル')
    groups = Array(@search_groups).map(&:name).join('・')
    ages = Array(@search_ages).map(&:name).join('・')
    audience = [groups.presence, ages.presence].compact.join('／')
    tag = @tag && (@tag.text.presence || "#{@tag.name}の")
    subject = "#{area.present? ? "#{area}の" : ''}#{audience.present? ? "#{audience}向けの" : ''}#{tag}#{activity}募集"
    subject += "（「#{params[:q]}」で検索）" if params[:q].present?
    subject
  end

end
