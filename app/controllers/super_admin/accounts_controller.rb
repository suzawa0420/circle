class SuperAdmin::AccountsController < ApplicationController
  before_action :require_webmaster!
  before_action :set_kind
  before_action :set_account, except: :index

  def index
    @accounts = @model.order(created_at: :desc)
    if params[:q].present?
      query = "%#{@model.sanitize_sql_like(params[:q].to_s.strip)}%"
      @accounts = @accounts.where('nickname ILIKE :q OR email ILIKE :q', q: query)
    end
    @accounts = @accounts.where.not(suspended_at: nil) if params[:state] == 'suspended'
    @accounts = @accounts.page(params[:page]).per(30)
  end

  def show
    @conversations = conversations.includes(:member, :user).order(updated_at: :desc).page(params[:page]).per(20)
    @reports = ChatReport.where(conversation_id: conversations.select(:id)).order(created_at: :desc).page(params[:report_page]).per(20)
    @reviews = if @kind == 'member'
      @account.received_conversation_reviews
    else
      Review.where(user_id: @account.users.select(:id))
    end.order(created_at: :desc).page(params[:review_page]).per(20)
  end

  def confirm
    @operation = params[:operation].to_s
    raise ActiveRecord::RecordNotFound unless %w[suspend resume delete].include?(@operation)
    raise ActiveRecord::RecordNotFound if @operation == 'delete' && @kind != 'owner'
    @impact = { circles: @kind == 'owner' ? @account.users.count : 0,
                conversations: conversations.count,
                messages: ChatMessage.where(conversation_id: conversations.select(:id)).count,
                reviews: @kind == 'owner' ? Review.where(user_id: @account.users.select(:id)).count : @account.received_conversation_reviews.count }
    @confirmation = @account.signed_id(purpose: "moderation:#{@operation}", expires_in: 15.minutes)
  end

  def update
    operation = params[:operation].to_s
    unless %w[suspend resume delete].include?(operation) && @model.find_signed(params[:confirmation], purpose: "moderation:#{operation}") == @account
      return redirect_to super_admin_account_path(@account, kind: @kind), alert: '確認画面から操作をやり直してください。'
    end
    if operation == 'delete'
      raise ActiveRecord::RecordNotFound unless @kind == 'owner'
      @account.destroy!
      return redirect_to super_admin_accounts_path(kind: @kind), notice: '主催者と関連データを削除しました。'
    end
    reason = params[:reason].to_s.strip
    if operation == 'suspend' && reason.blank?
      return redirect_to confirm_super_admin_account_path(@account, kind: @kind, operation: operation), alert: '停止理由を入力してください。'
    end
    @account.update!(suspended_at: operation == 'suspend' ? Time.current : nil, suspension_reason: operation == 'suspend' ? reason : nil)
    redirect_to super_admin_account_path(@account, kind: @kind), notice: operation == 'suspend' ? '利用を停止しました。' : '利用停止を解除しました。'
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey
    redirect_to super_admin_account_path(@account, kind: @kind), alert: '更新できませんでした。入力内容や関連データを確認してください。'
  end

  private
  def set_kind
    @kind = params[:kind].presence || 'member'
    @model = { 'member' => Member, 'owner' => AdminUser }.fetch(@kind) { raise ActiveRecord::RecordNotFound }
    @label = @kind == 'member' ? '参加者' : '主催者'
  end
  def set_account
    @account = @model.find(params[:id])
  end
  def conversations
    @kind == 'member' ? @account.conversations : Conversation.where(user_id: @account.users.select(:id))
  end
end
