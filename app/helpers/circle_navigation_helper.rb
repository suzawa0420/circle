module CircleNavigationHelper
  def redesigned_public_circle_page?(tab = circle_navigation_tab)
    tab == :details || (action_name == "index" && %i[schedules reviews questions blogs].include?(tab))
  end

  # Public circle pages only: editor and account screens keep the site header.
  def circle_navigation_tab
    return unless @user&.persisted?
    return if controller_path == 'schedules' && action_name == 'index' && can_manage_circle?(@user)

    case controller_path
    when "circles/circles"
      :details if action_name == "show"
    when "circles/blogs"
      :blogs if %w[index show].include?(action_name)
    when "reviews"
      :reviews if action_name == "index"
    when "schedules"
      :schedules if %w[index show].include?(action_name)
    when "questions"
      :questions if %w[index show].include?(action_name)
    end
  end
end
