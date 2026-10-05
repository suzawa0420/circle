class SuperAdmin::SupportRequestsController < ApplicationController
  before_action :require_webmaster!

  def index
    @status = SupportRequest::STATUSES.key?(params[:status]) ? params[:status] : 'pending'
    @requests = SupportRequest.where(status: @status).where.not(kind: 'suggestion')
      .order(Arel.sql("CASE WHEN kind = 'safety' THEN 0 ELSE 1 END"), created_at: :asc, id: :asc).page(params[:page]).per(30)
    @suggestion_count = SupportRequest.where(kind: 'suggestion', status: 'pending').count
    events = HelpEvent.where('created_at >= ?', 30.days.ago)
    @searches = events.where(kind: 'search').count
    @helpful = events.where(kind: 'helpful').count
    @unhelpful = events.where(kind: 'unhelpful').count
    @missing_queries = events.where(kind: 'search', result_count: 0).where.not(query: nil).group(:query).order(Arel.sql('COUNT(*) DESC')).limit(20).count
    @unhelpful_articles = events.where(kind: 'unhelpful').group(:article_id).order(Arel.sql('COUNT(*) DESC')).limit(10).count
    @categories = SupportRequest.where(kind: 'inquiry').where('created_at >= ?', 30.days.ago).group(:category).count
  end

  def show
    @support_request = SupportRequest.find(params[:id])
  end

  def update
    @support_request = SupportRequest.find(params[:id])
    if @support_request.update(params.require(:support_request).permit(:status, :staff_note))
      redirect_to super_admin_support_request_path(@support_request), notice: '対応状況を更新しました。メールは送信されません。'
    else
      render :show, status: :unprocessable_entity
    end
  end
end
