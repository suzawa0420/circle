class SuperAdmin::ConversationsController < ApplicationController
  before_action :require_webmaster!

  def index
    @query = params[:q].is_a?(String) ? params[:q].strip.first(100) : ''
    scope = Conversation.all
    if @query.present?
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
      scope = scope.where(user_id: User.where('name ILIKE ?', pattern).select(:id))
                   .or(scope.where(member_id: Member.where('nickname ILIKE ?', pattern).select(:id)))
    end
    latest = ChatMessage.select('conversation_id, MAX(id) AS latest_message_id, MAX(created_at) AS latest_message_at').group(:conversation_id)
    @conversations = scope.joins("INNER JOIN (#{latest.to_sql}) latest_chat ON latest_chat.conversation_id = conversations.id")
                          .select('conversations.*, latest_chat.latest_message_id, latest_chat.latest_message_at')
                          .includes(:member, user: :admin_user)
                          .order('latest_chat.latest_message_at DESC, latest_chat.latest_message_id DESC')
                          .page(params[:page]).per(30)
    @latest_messages = ChatMessage.where(id: @conversations.map(&:latest_message_id)).index_by(&:conversation_id)
  end

  def show
    @conversation = Conversation.includes(:member, user: :admin_user).find_by!(public_id: params[:id])
    @initial_jump = ConversationJump.new(@conversation).call if params[:page].blank? || params[:jump] == '1'
    if @initial_jump && (params[:page].blank? || params[:jump] == '1')
      redirect_to super_admin_conversation_path(@conversation, page: @initial_jump&.fetch(:page), anchor: ("chat-message-#{@initial_jump[:message_id]}" if @initial_jump))
      return
    end
    scope = @conversation.chat_messages.order(:id)
    @messages = scope.page(params[:page].presence || @initial_jump&.fetch(:page)).per(ConversationJump::PAGE_SIZE)
  end
end
