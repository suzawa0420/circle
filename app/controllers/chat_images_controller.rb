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
      owner_scope = admin_user_signed_in? ? Conversation.where(user_id: current_admin_user.users.select(:id)) : Conversation.none
      member_scope.or(owner_scope)
    end
    conversation = scope.find_by!(public_id: params[:conversation_id])
    message = conversation.chat_messages.find(params[:id])
    raise ActiveRecord::RecordNotFound unless message.image?

    send_data message.image.decrypted_image, type: 'image/jpeg', disposition: 'inline', filename: "photo-#{message.id}.jpg"
  end
end
