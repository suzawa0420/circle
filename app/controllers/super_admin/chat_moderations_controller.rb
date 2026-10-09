class SuperAdmin::ChatModerationsController < ApplicationController
  before_action :require_webmaster!

  def index
    @status = params[:status].in?(%w[held approved spam]) ? params[:status] : 'held'
    @pending_count = ChatMessage.where(moderation_status: 'held').count
    @messages = ChatMessage.where(moderation_status: @status).includes(conversation: [:member, :user]).order(id: :desc).page(params[:page]).per(20)
  end

  def update
    message = ChatMessage.find(params[:id])
    return head :unprocessable_entity unless params[:decision].in?(%w[approve spam])
    changed = message.moderate!(params[:decision])
    redirect_to super_admin_chat_moderations_path, notice: changed ? (params[:decision] == 'approve' ? '配信を許可しました。相手に新着として届きます。' : 'スパムとして確認しました。相手には配信しません。') : 'この投稿は確認済みです。'
  end
end
