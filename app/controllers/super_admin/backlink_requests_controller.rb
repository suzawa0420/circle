class SuperAdmin::BacklinkRequestsController < ApplicationController
  before_action :require_webmaster!

  def index
    @status = BacklinkRequest::STATUSES.key?(params[:status]) ? params[:status] : 'pending'
    @status_counts = BacklinkRequest.group(:status).count
    @requests = BacklinkRequest.includes(user: :admin_user).where(status: @status).order(submitted_at: :asc, id: :asc).page(params[:page]).per(30)
  end

  def show
    @backlink_request = BacklinkRequest.find(params[:id])
  end

  def update
    @backlink_request = BacklinkRequest.find(params[:id])
    changed = @backlink_request.review!(params[:decision], current_webmaster, params[:review_note])
    redirect_to super_admin_backlink_request_path(@backlink_request), notice: changed ? '審査結果とポイントを更新しました。' : '現在の申請状況ではこの操作はできません。'
  rescue ActiveRecord::RecordInvalid => e
    @backlink_request = e.record if e.record.is_a?(BacklinkRequest)
    @backlink_request.status = @backlink_request.status_in_database || 'pending'
    render :show, status: :unprocessable_entity
  end
end
