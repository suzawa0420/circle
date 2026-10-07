class MembersController < ApplicationController
  before_action :authenticate_member!, only: [:show, :edit, :update]
  before_action :set_own_member, only: [:show, :edit, :update]
  before_action :load_profile_options, only: [:edit, :update]

  def index
    redirect_to circles_path
  end

  def show
    @bookmarked_circles = User.publicly_visible.where(id: @member.bookmarks.select(:user_id)).includes(:event, :prefecture).order(created_at: :desc).page(params[:page]).per(12)
    @conversations_count = @member.conversations.where(id: ChatMessage.select(:conversation_id)).count
    @unread_count = @member.conversations.where('EXISTS (SELECT 1 FROM chat_messages WHERE chat_messages.conversation_id = conversations.id AND chat_messages.sender_role = ? AND chat_messages.moderation_status IN (?, ?) AND ((chat_messages.released_at IS NULL AND chat_messages.id > conversations.member_read_message_id) OR (chat_messages.released_at IS NOT NULL AND chat_messages.recipient_read_at IS NULL)))', 'owner', 'delivered', 'approved').count
    @recommended_circles = if @member.prefecture_id.present? && @member.events.exists?
      User.publicly_visible.where(prefecture_id: @member.prefecture_id).or(User.publicly_visible.where(prefecture_sub_id: @member.prefecture_id))
          .where(event_id: @member.events.select(:id)).where.not(id: @member.bookmarks.select(:user_id))
          .includes(:event, :prefecture).order(last_post: :desc).limit(4)
    else
      User.none
    end
    @answers = EventAnswer.where(member_id: @member.id).includes(event_question: :event).order(created_at: :desc).limit(10)
  end

  def edit; end

  def update
    @member.random_id ||= SecureRandom.alphanumeric(6)
    saved = Member.transaction do
      @member.assign_attributes(member_params)
      @member.save(context: :profile) || raise(ActiveRecord::Rollback)
    end
    if saved
      redirect_to member_path(@member), notice: 'プロフィールを更新しました。'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_own_member
    return head :forbidden unless current_member.id == params[:id].to_i
    @member = current_member
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['X-Robots-Tag'] = 'noindex, nofollow'
  end

  def load_profile_options
    @event_groups = Event.includes(:category).order(:order, :id).group_by(&:category)
    @prefectures = Prefecture.where.not(kana: 'online').order(:order, :id)
  end

  def member_params
    params.require(:member).permit(:nickname, :image_profile, :gender, :profile, :prefecture_id, :date_of_birth, event_ids: [])
  end
end
