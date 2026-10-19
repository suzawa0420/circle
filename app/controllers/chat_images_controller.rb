class ChatImagesController < ApplicationController
  def show
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['X-Robots-Tag'] = 'noindex, nofollow'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    unless webmaster? || member_signed_in? || admin_user_signed_in?
      return head :unauthorized
    end

    scope = if webmaster?
      Conversation.all
    else
      member_scope = member_signed_in? ? Conversation.where(member_id: current_member.id) : Conversation.none
      owner_scope = admin_user_signed_in? ? Conversation.for_owner(current_admin_user) : Conversation.none
      member_scope.or(owner_scope)
    end
    conversation = scope.find_by!(public_id: params[:conversation_id])
    message = conversation.chat_messages.find(params[:id])
    role = conversation.role_for(current_member, current_admin_user)
    raise ActiveRecord::RecordNotFound unless message.deleted_at.nil? && message.image? && (webmaster? || message.delivered? || message.sender_role == role)

    send_data message.image.decrypted_image, type: 'image/jpeg', disposition: 'inline', filename: "photo-#{message.id}.jpg"
  end
end
