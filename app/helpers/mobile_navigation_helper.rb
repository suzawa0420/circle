module MobileNavigationHelper
  def mobile_navigation_circle
    return @mobile_navigation_circle if defined?(@mobile_navigation_circle)

    candidate = @user if @user.is_a?(User)
    candidate ||= @conversation&.user if @conversation.is_a?(Conversation)
    @mobile_navigation_circle = if candidate && candidate.admin_user_id == current_admin_user.id
      session[:managed_circle_id] = candidate.id if request.get?
      candidate
    else
      current_admin_user.users.find_by(id: session[:managed_circle_id]) || current_admin_user.users.first
    end
  end

  def mobile_circle_switcher?
    return false unless admin_user_signed_in? && controller_path != 'conversations'

    owned_context = @user.is_a?(User) && @user.admin_user_id == current_admin_user.id
    owned_context || (controller_path == 'admin_users/registrations' && %w[edit update].include?(action_name))
  end

  def mobile_circle_switch_path(circle)
    case controller_path
    when 'circles/blogs' then new_circle_blog_path(circle)
    when 'schedules'
      %w[new create].include?(action_name) ? new_user_schedule_path(circle) : user_schedules_path(circle)
    when 'questions' then user_questions_path(circle)
    when 'reviews' then user_reviews_path(circle)
    when 'user_contacts' then "/users/#{circle.id}/contact_list"
    when 'links' then new_user_link_path(circle)
    when 'matches' then new_user_match_path(circle)
    when 'users'
      return inquiry_settings_path(circle) if %w[inquiry_settings update_inquiry_settings].include?(action_name)
      return "/users/#{circle.id}/account_del" if action_name == 'account_del'
      %w[edit update edit2 update2 edit3 update3].include?(action_name) ? edit_user_path(circle) : "/users/#{circle.id}/mypage"
    else "/users/#{circle.id}/mypage"
    end
  end

  def mobile_navigation_unread_count
    return @mobile_navigation_unread_count if defined?(@mobile_navigation_unread_count)

    if admin_user_signed_in?
      conversations = Conversation.where(user_id: current_admin_user.users.select(:id))
      role, incoming = 'owner', 'member'
    elsif member_signed_in?
      conversations = current_member.conversations
      role, incoming = 'member', 'owner'
    else
      return 0
    end
    @mobile_navigation_unread_count = conversations.where(
      "EXISTS (SELECT 1 FROM chat_messages WHERE chat_messages.conversation_id = conversations.id AND chat_messages.sender_role = ? AND chat_messages.id > conversations.#{role}_read_message_id)",
      incoming
    ).count
  end
end
