module MobileNavigationHelper
  def mobile_navigation_circle
    return @mobile_navigation_circle if defined?(@mobile_navigation_circle)

    candidate = @user if @user.is_a?(User)
    candidate ||= @conversation&.user if @conversation.is_a?(Conversation)
    @mobile_navigation_circle = if candidate && candidate.admin_user_id == current_admin_user.id
      candidate
    else
      current_admin_user.users.first
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
