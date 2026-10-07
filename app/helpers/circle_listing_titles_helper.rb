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
    safe_join([
      content_tag(:span, count.delete_prefix('【'), class: 'circle-listing-heading__count'),
      content_tag(:span, subject, class: 'circle-listing-heading__subject')
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
