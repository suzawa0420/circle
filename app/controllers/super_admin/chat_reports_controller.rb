class SuperAdmin::ChatReportsController < ApplicationController
  before_action :require_webmaster!
  before_action do
    head :forbidden unless webmaster?
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['X-Robots-Tag'] = 'noindex, nofollow'
  end

  def index
    @reports = ChatReport.all
    @reports = @reports.where(status: params[:status]) if ChatReport::STATUSES.key?(params[:status])
    @reports = @reports.includes(conversation: [:user, :member]).order(resolved_at: :asc, created_at: :desc).page(params[:page]).per(30)
  end

  def show
    @report = ChatReport.find(params[:id])
    @messages = @report.conversation.chat_messages.order(:id).page(params[:page]).per(50)
  end

  def update
    @report = ChatReport.find(params[:id])
    attributes = params[:chat_report] ? params.require(:chat_report).permit(:status, :operational_memo) : { status: 'resolved' }
    if @report.update(attributes)
      redirect_to super_admin_chat_report_path(@report), notice: '対応状況と運営メモを保存しました。'
    else
      @messages = @report.conversation.chat_messages.order(:id).page(params[:page]).per(50)
      render :show, status: :unprocessable_entity
    end
  end
end
