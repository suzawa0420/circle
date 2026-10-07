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
    count, bracket, subject = circle_listing_title.partition('】')
    safe_join([
      content_tag(:span, count + bracket, class: 'circle-listing-heading__count'),
      content_tag(:span, subject, class: 'circle-listing-heading__subject')
    ])
  end

  def circle_listing_subject
    if controller_path == 'circles/search'
      return "条件で絞り込んだサークル・チーム検索結果" if params[:detailed] == "1" && params[:q].blank?
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
end
