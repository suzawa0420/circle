class ConversationsController < ApplicationController
  before_action :authenticate_chat_account!
  before_action :private_page
  before_action :load_conversation, except: [:index, :new, :create]
  before_action :require_verified_chat_sender, only: [:new, :create, :message, :review, :update_message, :delete_message, :reaction]
  before_action :require_japanese_member_profile, only: [:new, :create, :message]
  rescue_from Conversation::NotAllowed, with: :invalid_action
  rescue_from ActiveRecord::RecordInvalid, with: :invalid_record

  def index
    inbox_scope = accessible_conversations
    if admin_user_signed_in? && !member_signed_in?
      inbox_scope = inbox_scope.where(user_id: params[:circle_id]).or(inbox_scope.where(source_user_id: params[:circle_id])) if params[:circle_id].present?
      @penalty_count = inbox_scope.reported_unanswered.count
      @penalty_only = params[:penalty] == '1'
      inbox_scope = inbox_scope.reported_unanswered if @penalty_only
    end
    visible = ChatMessage.deliverable
    visible = visible.or(ChatMessage.where(sender_role: 'member', conversation_id: Conversation.where(member_id: current_member.id).select(:id))) if member_signed_in?
    if admin_user_signed_in?
      visible = visible.or(ChatMessage.where(sender_role: 'member', conversation_id: Conversation.where(source_user_id: current_admin_user.users.select(:id)).select(:id)))
    end
    # Automatic guidance alone must not expose an inquiry held before delivery.
    latest = visible.where(conversation_id: inbox_scope.select(:id)).where.not(sender_role: 'system').select('conversation_id, MAX(GREATEST(COALESCE(released_at, created_at), edited_at, deleted_at)) AS delivered_at, MAX(id) AS latest_id').group(:conversation_id)
    notes = inbox_private_notes
    note_activity = notes.select('conversation_id, MAX(updated_at) AS noted_at').group(:conversation_id)
    @conversations = inbox_scope.joins("INNER JOIN (#{latest.to_sql}) inbox ON inbox.conversation_id = conversations.id")
      .joins("LEFT JOIN (#{note_activity.to_sql}) inbox_notes ON inbox_notes.conversation_id = conversations.id")
      .select('conversations.*, GREATEST(inbox.delivered_at, inbox_notes.noted_at) AS inbox_updated_at')
      .includes(:conversation_reviews, :member, :source_user, user: :admin_user)
      .order(Arel.sql('GREATEST(inbox.delivered_at, inbox_notes.noted_at) DESC, inbox.latest_id DESC, conversations.id DESC')).page(params[:page]).per(20)
    ids = @conversations.map(&:id)
    @private_notes = notes.where(conversation_id: ids).index_by { |note| [note.conversation_id, note.member_id, note.admin_user_id] }
    @no_show_conversation_ids = NoShowReport.where(conversation_id: ids).distinct.pluck(:conversation_id)
    @penalty_ids = Conversation.reported_unanswered.where(id: ids).pluck(:id)
    @latest_messages = visible.where(conversation_id: ids).select('DISTINCT ON (conversation_id) chat_messages.*').order(:conversation_id).delivery_order.index_by(&:conversation_id)
    @unread_counts = %w[member owner].index_with do |role|
      incoming = role == 'member' ? 'owner' : 'member'
      ChatMessage.deliverable.joins(:conversation).where(conversation_id: ids, sender_role: incoming)
        .where("(chat_messages.released_at IS NULL AND chat_messages.id > conversations.#{role}_read_message_id) OR (chat_messages.released_at IS NOT NULL AND chat_messages.recipient_read_at IS NULL)").group(:conversation_id).count
    end
  end

  def new
    @user = User.publicly_visible.find(params[:user_id])
    if practice_match_request?
      raise Conversation::NotAllowed, '練習試合のメッセージ機能を準備しています。少し待ってからお試しください。' unless Conversation::PRACTICE_MATCH_ENABLED
      @source_circles = current_admin_user.users.publicly_visible.order(:id)
      return render :new_practice_match
    end
    @inquiry_context = CircleInquiryContext.resolve(@user, params[:inquiry_context])
    existing = Conversation.find_by(user: @user, member: current_member)
    return redirect_to conversation_path(existing) if existing && existing.chat_messages.exists? && @inquiry_context.blank?
    @inquiry_guidance = CircleInquiryGuidance.new(@user).messages
  end

  def private_note
    body = params.require(:note).permit(:body).fetch(:body).to_s
    attributes = ConversationNote.account_attributes(private_note_account(@conversation))
    note = ConversationNote.transaction do
      note = @conversation.conversation_notes.find_by(attributes) || @conversation.conversation_notes.create_or_find_by!(attributes)
      note.with_lock { note.update!(body: body) }
      note
    end
    respond_to do |format|
      format.json { render json: { saved: true, updated_at: note.updated_at.iso8601(6) } }
      format.html { redirect_to conversations_path, notice: 'メモを保存しました。' }
    end
  rescue ActiveRecord::RecordInvalid
    respond_to do |format|
      format.json { render json: { error: 'メモは300文字以内で入力してください。' }, status: :unprocessable_entity }
      format.html { redirect_to conversations_path, alert: 'メモは300文字以内で入力してください。' }
    end
  end

  def create
    @user = User.publicly_visible.find(params[:user_id])
    return create_practice_match if practice_match_request?
    raise Conversation::NotAllowed, '現在、このサークルは募集を停止しています。' unless @user.switch == '募集中'
    raise Conversation::NotAllowed, 'ご自身のサークルには問い合わせできません。' if current_admin_user&.id == @user.admin_user_id || @user.admin_user.email.casecmp?(current_member.email)
    current_member.with_lock do
      if current_member.conversations.where('created_at > ?', 1.day.ago).count >= 20
        raise Conversation::NotAllowed, '本日の問い合わせ上限に達しました。明日お試しください。'
      end
      @conversation = Conversation.for_member!(@user, current_member)
      @sent_message = @conversation.send_message!('member', params.require(:message).permit(:body)[:body], inquiry_context: CircleInquiryContext.resolve(@user, params[:inquiry_context]))
    end
    flash[:sport_inquiry_delivered] = @user.event.ruby if @sent_message.delivered?
    redirect_to conversation_path(@conversation), notice: @sent_message.delivered? ? 'お問い合わせを送信しました。' : '運営による確認後に配信します。相手にはまだ届いていません。'
  end

  def show
    if params[:edit_message_id].present? && !@editing_message
      @editing_message = @conversation.chat_messages.find(params[:edit_message_id])
      unless @editing_message.changeable_by?(@role)
        raise Conversation::NotAllowed, '自分が送信した12時間以内のメッセージのみ編集・削除できます。'
      end
      @draft_body = @editing_message.body
    end
    @conversation.publish_reviews!
    @review_prompt_due = @conversation.review_prompt_due?(@role)
    @initial_jump = ConversationJump.new(@conversation, role: @role).call if params[:page].blank?
    @messages = @conversation.chat_messages.visible_to(@role).includes(:chat_message_reactions).delivery_order.page(params[:page].presence || @initial_jump&.fetch(:page)).per(ConversationJump::PAGE_SIZE).load
    mark_messages_read(advance_cursor: params[:page].blank? || params[:page] == '1')
    @own_review = @conversation.conversation_reviews.find_by(author_role: @role)
    @public_reviews = @conversation.conversation_reviews.publicly_visible.order(:id)
  end

  def messages
    @messages = @conversation.chat_messages.visible_to(@role).includes(:chat_message_reactions).delivery_order.limit(50).load
    mark_messages_read
    render json: { latest_id: @messages.first&.id || 0,
                   html: render_to_string(partial: 'messages', formats: [:html]),
                   history_version: history_version,
                   receipts: @messages.reject(&:automatic?).select { |m| m.sender_role == @role }.to_h { |m| [m.id, m.receipt_text(@conversation)] },
                   recipient_read_id: @conversation.recipient_read_message_id(@role),
                   accepted: @conversation.accepted_at.present?,
                   review_prompt_html: @conversation.review_prompt_due?(@role) ? render_to_string(partial: "review_prompt", formats: [:html]) : "" }
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
    redirect_to conversation_path(@conversation), notice: @conversation.practice_match? ? 'ブロックしました。過去の履歴は残ります。' : 'ブロックしました。評価権や過去の履歴は残ります。'
  end

  def update_message
    message = @conversation.chat_messages.find(params[:message_id])
    message.revise!(@role, body: params.require(:message).permit(:body).fetch(:body))
    redirect_to conversation_path(@conversation, anchor: "chat-message-#{message.id}"), notice: 'メッセージを編集しました。'
  rescue ActiveRecord::RecordInvalid => error
    @editing_message = message
    @draft_body = params[:message][:body].to_s
    @message_error = error.record.errors.full_messages.join('、')
    show
    render :show, status: :unprocessable_entity
  end

  def delete_message
    message = @conversation.chat_messages.find(params[:message_id])
    message.revise!(@role, delete: true)
    redirect_to conversation_path(@conversation, anchor: "chat-message-#{message.id}"), notice: 'メッセージを削除しました。'
  end

  def reaction
    message = @conversation.chat_messages.find(params[:message_id])
    key = params.require(:reaction).permit(:key).fetch(:key) { raise ActionController::ParameterMissing, :key }
    message.set_reaction!(@role, key.to_s)
    respond_to do |format|
      format.json { render json: { html: render_to_string(partial: 'conversations/reactions', locals: { message: message }, formats: [:html]) } }
      format.html { redirect_to conversation_path(@conversation, anchor: "chat-message-#{message.id}") }
    end
  rescue Conversation::NotAllowed, ActiveRecord::RecordInvalid => error
    respond_to do |format|
      format.json { render json: { error: error.is_a?(Conversation::NotAllowed) ? error.message : 'リアクションを保存できませんでした。' }, status: :unprocessable_entity }
      format.html { redirect_to conversation_path(@conversation, anchor: "chat-message-#{message.id}"), alert: 'リアクションを保存できませんでした。' }
    end
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

  def review_prompt
    @conversation.update_review_prompt!(@role, params[:choice])
    notice = params[:choice] == 'later' ? '7日後にもう一度ご案内します。投稿期限を過ぎた場合は表示しません。' : 'このやり取りの口コミ案内を停止しました。投稿期限内はいつでも感想を書けます。'
    redirect_to conversation_path(@conversation), notice: notice
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
    @conversation.report_no_reply!(@role)
    redirect_to conversation_path(@conversation), notice: '返信がないことを報告しました。'
  end

  def no_show_report
    raise Conversation::NotAllowed, '主催者のみ報告できます。' unless @role == 'owner' && !@conversation.practice_match?
    @conversation.ensure_active_sender!('owner')
    raise Conversation::NotAllowed, 'メールアドレスを確認してください。' unless current_admin_user.email_verified?
    @no_show_draft = @conversation.no_show_reports.new(params.require(:no_show_report).permit(:scheduled_at, :participation_confirmed, :no_advance_notice))
    @conversation.with_lock do
      @no_show_draft.save!
    end
    redirect_to conversation_path(@conversation, anchor: 'attendance-reports'), notice: '欠席についての申告を記録しました。参加者本人は説明・異議申し立てを送れます。'
  rescue ActiveRecord::RecordInvalid
    show
    render :show, status: :unprocessable_entity
  end

  def no_show_response
    raise Conversation::NotAllowed, '参加者本人のみ説明を送れます。' unless @role == 'member' && !@conversation.practice_match?
    report = @conversation.no_show_reports.find(params[:report_id])
    report.with_lock do
      report.update!(member_response: params.require(:no_show_report).permit(:member_response)[:member_response].to_s,
                     member_responded_at: Time.current)
    end
    redirect_to conversation_path(@conversation, anchor: 'attendance-reports'), notice: '説明・異議申し立てを保存しました。返信がないことだけを理由に運営確認済みにはしません。'
  end

  private

  def inbox_private_notes
    notes = ConversationNote.none
    if member_signed_in?
      member_conversations = Conversation.where(member_id: current_member.id, source_user_id: nil)
      notes = notes.or(ConversationNote.for_account(current_member).where(conversation_id: member_conversations.select(:id)))
    end
    if admin_user_signed_in?
      owner_conversations = Conversation.for_owner(current_admin_user)
      owner_conversations = owner_conversations.where('conversations.member_id IS NULL OR conversations.member_id <> ?', current_member.id) if member_signed_in?
      notes = notes.or(ConversationNote.for_account(current_admin_user).where(conversation_id: owner_conversations.select(:id)))
    end
    notes
  end

  helper_method :private_note_account
  def private_note_account(conversation)
    conversation.role_for(current_member, current_admin_user) == 'member' && !conversation.practice_match? ? current_member : current_admin_user
  end

  def practice_match_request?
    (%w[new create].include?(action_name) && params[:kind] == 'practice_match') || @conversation&.practice_match?
  end

  def create_practice_match
    source = current_admin_user.users.publicly_visible.find(params[:source_user_id])
    raise Conversation::NotAllowed, '現在、このサークルは対戦相手を募集していません。' unless @user.match&.recruit == '募集中'
    raise Conversation::NotAllowed, '利用停止中のサークルには問い合わせできません。' if @user.admin_user.suspended?
    current_admin_user.with_lock do
      if Conversation.where(source_user_id: current_admin_user.users.select(:id)).where('created_at > ?', 1.day.ago).count >= 20
        raise Conversation::NotAllowed, '本日の問い合わせ上限に達しました。明日お試しください。'
      end
      @conversation = Conversation.for_circles!(@user, source)
      @role = @conversation.role_for(nil, current_admin_user)
      @sent_message = @conversation.send_message!(@role, params.require(:message).permit(:body)[:body])
    end
    redirect_to conversation_path(@conversation), notice: @sent_message.delivered? ? '練習試合の相談を送信しました。' : '運営による確認後に配信します。相手にはまだ届いていません。'
  end

  def mark_messages_read(advance_cursor: true)
    return if webmaster_signed_in?

    @conversation.mark_read!(@role, through: advance_cursor ? (@messages.map(&:id).max || 0) : 0, message_ids: @messages.map(&:id))
    @messages.each { |m| m.reload if m.released_at }
  end

  helper_method :history_version
  def history_version
    Digest::SHA256.hexdigest(@messages.map { |m| [m.id, m.moderation_status, m.released_at&.iso8601(6), m.edited_at&.iso8601(6), m.deleted_at&.iso8601(6), m.changeable_by?(@role), m.reactable?, m.chat_message_reactions.sort_by(&:id).map { |r| [r.id, r.key] }] }.to_json)
  end

  def private_page
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['X-Robots-Tag'] = 'noindex, nofollow'
    response.headers['Referrer-Policy'] = 'same-origin'
  end

  def authenticate_chat_account!
    if practice_match_request? && !admin_user_signed_in?
      store_location_for(:admin_user, request.fullpath) if request.get?
      return redirect_to new_admin_user_session_path, alert: '練習試合の相談には主催者アカウントでログインしてください。'
    end
    return if member_signed_in? || admin_user_signed_in?
    store_location_for(:member, request.fullpath) if request.get?
    if %w[new create].include?(action_name)
      redirect_to new_member_registration_path, alert: 'お問い合わせには無料の参加者登録が必要です。'
    else
      store_location_for(:admin_user, request.fullpath) if request.get?
      redirect_to login_path, alert: 'メッセージを確認するにはログインしてください。'
    end
  end

  def require_japanese_member_profile
    return if practice_match_request? || @role == 'owner' || !member_signed_in? || current_member.japanese_profile?
    redirect_to edit_member_path(current_member), alert: '自己紹介を日本語（ひらがな・カタカナを含む文章）に修正してから送信してください。'
  end

  def require_verified_chat_sender
    owner_sender = practice_match_request? || @role == 'owner'
    actor = owner_sender ? current_admin_user : current_member
    raise Conversation::NotAllowed, '利用停止中は問い合わせ・メッセージ・口コミを投稿できません。' if actor&.suspended?
    if owner_sender
      unless current_admin_user.email_verified?
        store_location_for(:admin_user, @conversation ? conversation_path(@conversation) : new_user_conversation_path(params[:user_id], kind: 'practice_match'))
        redirect_to admin_user_email_verification_path
      end
      return
    end
    unless member_signed_in?
      return redirect_to new_member_registration_path, alert: '無料の参加者登録をしてご利用ください。'
    end
    unless current_member.email_verified?
      store_location_for(:member, @conversation ? conversation_path(@conversation) : new_user_conversation_path(params[:user_id], inquiry_context: params[:inquiry_context]))
      redirect_to member_email_verification_path
    end
  end

  def accessible_conversations
    member_scope = member_signed_in? ? Conversation.where(member_id: current_member.id) : Conversation.none
    owner_scope = admin_user_signed_in? ? Conversation.for_owner(current_admin_user) : Conversation.none
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
    @role = @conversation.role_for(current_member, current_admin_user)
  end

  def invalid_action(error)
    redirect_to(@conversation&.persisted? ? conversation_path(@conversation) : conversations_path, alert: error.message)
  end

  def invalid_record(error)
    redirect_to(@conversation&.persisted? && Conversation.exists?(@conversation.id) ? conversation_path(@conversation) : new_user_conversation_path(params[:user_id], kind: params[:kind]),
                alert: error.record.errors.full_messages.join('、'))
  end
end
