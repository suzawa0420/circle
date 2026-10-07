class ConversationsController < ApplicationController
  before_action :authenticate_chat_account!
  before_action :private_page
  before_action :load_conversation, except: [:index, :new, :create]
  before_action :require_verified_chat_sender, only: [:new, :create, :message, :review]
  rescue_from Conversation::NotAllowed, with: :invalid_action
  rescue_from ActiveRecord::RecordInvalid, with: :invalid_record

  def index
    inbox_scope = accessible_conversations
    visible = ChatMessage.deliverable
    visible = visible.or(ChatMessage.where(sender_role: 'member', conversation_id: Conversation.where(member_id: current_member.id).select(:id))) if member_signed_in?
    # Automatic guidance alone must not expose an inquiry held before delivery.
    latest = visible.where(conversation_id: inbox_scope.select(:id)).where.not(sender_role: 'system').select('conversation_id, MAX(COALESCE(released_at, created_at)) AS delivered_at, MAX(id) AS latest_id').group(:conversation_id)
    @conversations = inbox_scope.joins("INNER JOIN (#{latest.to_sql}) inbox ON inbox.conversation_id = conversations.id")
      .includes(:user, :member).order('inbox.delivered_at DESC, inbox.latest_id DESC').page(params[:page]).per(20)
    ids = @conversations.map(&:id)
    @latest_messages = visible.where(conversation_id: ids).select('DISTINCT ON (conversation_id) chat_messages.*').order(:conversation_id).delivery_order.index_by(&:conversation_id)
    @unread_counts = %w[member owner].index_with do |role|
      incoming = role == 'member' ? 'owner' : 'member'
      ChatMessage.deliverable.joins(:conversation).where(conversation_id: ids, sender_role: incoming)
        .where("(chat_messages.released_at IS NULL AND chat_messages.id > conversations.#{role}_read_message_id) OR (chat_messages.released_at IS NOT NULL AND chat_messages.recipient_read_at IS NULL)").group(:conversation_id).count
    end
  end

  def new
    @user = User.publicly_visible.find(params[:user_id])
    existing = Conversation.find_by(user: @user, member: current_member)
    return redirect_to conversation_path(existing) if existing && existing.chat_messages.exists?
    @inquiry_guidance = CircleInquiryGuidance.new(@user).messages
  end

  def create
    @user = User.publicly_visible.find(params[:user_id])
    raise Conversation::NotAllowed, '現在、このサークルは募集を停止しています。' unless @user.switch == '募集中'
    raise Conversation::NotAllowed, 'ご自身のサークルには問い合わせできません。' if current_admin_user&.id == @user.admin_user_id || @user.admin_user.email.casecmp?(current_member.email)
    current_member.with_lock do
      if current_member.conversations.where('created_at > ?', 1.day.ago).count >= 20
        raise Conversation::NotAllowed, '本日の問い合わせ上限に達しました。明日お試しください。'
      end
      @conversation = Conversation.for_member!(@user, current_member)
      @sent_message = @conversation.send_message!('member', params.require(:message).permit(:body)[:body])
    end
    redirect_to conversation_path(@conversation), notice: @sent_message.delivered? ? 'お問い合わせを送信しました。' : '運営による確認後に配信します。相手にはまだ届いていません。'
  end

  def show
    @conversation.publish_reviews!
    @messages = @conversation.chat_messages.visible_to(@role).delivery_order.page(params[:page]).per(50).load
    mark_messages_read(advance_cursor: params[:page].blank? || params[:page] == '1')
    @own_review = @conversation.conversation_reviews.find_by(author_role: @role)
    @public_reviews = @conversation.conversation_reviews.publicly_visible.order(:id)
  end

  def messages
    @messages = @conversation.chat_messages.visible_to(@role).delivery_order.limit(50).load
    mark_messages_read
    render json: { latest_id: @messages.first&.id || 0,
                   html: render_to_string(partial: 'messages', formats: [:html]),
                   history_version: history_version,
                   receipts: @messages.reject(&:automatic?).select { |m| m.sender_role == @role }.to_h { |m| [m.id, m.receipt_text(@conversation)] },
                   recipient_read_id: @conversation.recipient_read_message_id(@role),
                   accepted: @conversation.accepted_at.present? }
  end

  def message
    attributes = params.require(:message)
    upload = attributes[:image]
    if upload.present? && !upload.is_a?(ActionDispatch::Http::UploadedFile)
      raise Conversation::NotAllowed, '画像は1メッセージにつき1枚だけ選択してください。'
    end
    @conversation.send_message!(@role, attributes.permit(:body)[:body], image: upload.presence)
    redirect_to conversation_path(@conversation)
  rescue ActiveRecord::RecordInvalid => error
    @message_error = error.record.errors.full_messages.join('、')
    @draft_body = attributes[:body].to_s.first(2000)
    show
    render :show, status: :unprocessable_entity
  end

  def block
    @conversation.with_lock { @conversation.update!("#{@role}_blocked" => true) }
    redirect_to conversation_path(@conversation), notice: 'ブロックしました。評価権や過去の履歴は残ります。'
  end

  def unblock
    @conversation.with_lock { @conversation.update!("#{@role}_blocked" => false) }
    redirect_to conversation_path(@conversation), notice: 'ご自身のブロックを解除しました。'
  end

  def review
    attributes = params.require(:evaluation).permit(:score, :comment, :participated)
    @conversation.submit_review!(@role, attributes)
    redirect_to conversation_path(@conversation), notice: '口コミを保存しました。双方の投稿完了または期限終了で公開します。'
  end

  def delete_review
    @conversation.delete_review!(@role)
    redirect_to conversation_path(@conversation), notice: '自分の口コミを削除しました。相手の口コミには影響しません。'
  end

  def report
    report = @conversation.chat_reports.new(reason: params.require(:report).permit(:reason)[:reason], reporter_role: @role)
    report.chat_message = @conversation.chat_messages.visible_to(@role).find(params[:message_id]) if params[:message_id].present?
    if params[:review_id].present?
      report.conversation_review = @conversation.conversation_reviews.publicly_visible.find(params[:review_id])
    end
    report.save!
    redirect_to conversation_path(@conversation), notice: '運営への通報を受け付けました。内容は相手には表示されません。'
  end

  def no_reply
    raise Conversation::NotAllowed, 'この操作はできません。' unless @role == 'member'
    @conversation.with_lock do
      raise Conversation::NotAllowed, '配信済みのお問い合わせがありません。' unless @conversation.chat_messages.deliverable.where(sender_role: 'member').exists?
      raise Conversation::NotAllowed, '返信済みの問い合わせです。' if @conversation.accepted_at
      @conversation.update!(respond_check: 'NG')
      @conversation.refresh_circle_score!
    end
    redirect_to conversation_path(@conversation), notice: '返信がないことを報告しました。'
  end

  private

  def mark_messages_read(advance_cursor: true)
    return if webmaster_signed_in?

    @conversation.mark_read!(@role, through: advance_cursor ? (@messages.map(&:id).max || 0) : 0, message_ids: @messages.map(&:id))
    @messages.each { |m| m.reload if m.released_at }
  end

  helper_method :history_version
  def history_version
    Digest::SHA256.hexdigest(@messages.map { |m| [m.id, m.moderation_status, m.released_at&.iso8601(6)] }.to_json)
  end

  def private_page
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['X-Robots-Tag'] = 'noindex, nofollow'
    response.headers['Referrer-Policy'] = 'same-origin'
  end

  def authenticate_chat_account!
    return if member_signed_in? || admin_user_signed_in?
    store_location_for(:member, request.fullpath) if request.get?
    if %w[new create].include?(action_name)
      redirect_to new_member_registration_path, alert: 'お問い合わせには無料の参加者登録が必要です。'
    else
      store_location_for(:admin_user, request.fullpath) if request.get?
      redirect_to login_path, alert: 'メッセージを確認するにはログインしてください。'
    end
  end

  def require_verified_chat_sender
    actor = @role == 'owner' ? current_admin_user : current_member
    raise Conversation::NotAllowed, '利用停止中は問い合わせ・メッセージ・口コミを投稿できません。' if actor&.suspended?
    if @role == 'owner'
      unless current_admin_user.email_verified?
        store_location_for(:admin_user, conversation_path(@conversation))
        redirect_to admin_user_email_verification_path
      end
      return
    end
    unless member_signed_in?
      return redirect_to new_member_registration_path, alert: '無料の参加者登録をしてご利用ください。'
    end
    unless current_member.email_verified?
      store_location_for(:member, @conversation ? conversation_path(@conversation) : new_user_conversation_path(params[:user_id]))
      redirect_to member_email_verification_path
    end
  end

  def accessible_conversations
    member_scope = member_signed_in? ? Conversation.where(member_id: current_member.id) : Conversation.none
    owner_scope = admin_user_signed_in? ? Conversation.where(user_id: current_admin_user.users.select(:id)) : Conversation.none
    member_scope.or(owner_scope)
  end

  def load_conversation
    identifier = params[:id].to_s
    @conversation = if identifier.match?(/\A\d+\z/)
      accessible_conversations.find(identifier)
    else
      accessible_conversations.find_by!(public_id: identifier)
    end
    if identifier != @conversation.public_id && request.get? && action_name == 'show'
      return redirect_to conversation_path(@conversation), status: :moved_permanently
    end
    @role = if member_signed_in? && @conversation.member_id == current_member.id
              'member'
            else
              'owner'
            end
  end

  def invalid_action(error)
    redirect_to(@conversation&.persisted? ? conversation_path(@conversation) : conversations_path, alert: error.message)
  end

  def invalid_record(error)
    redirect_to(@conversation&.persisted? ? conversation_path(@conversation) : new_user_conversation_path(params[:user_id]),
                alert: error.record.errors.full_messages.join('、'))
  end
end
