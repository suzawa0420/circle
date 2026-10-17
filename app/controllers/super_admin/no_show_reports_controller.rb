class SuperAdmin::NoShowReportsController < ApplicationController
  before_action :require_webmaster!
  before_action do
    head :forbidden unless webmaster?
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['X-Robots-Tag'] = 'noindex, nofollow'
  end

  def index
    @reports = NoShowReport.includes(conversation: [:member, :user]).order(created_at: :desc).page(params[:page]).per(30)
  end

  def show
    @report = NoShowReport.find(params[:id])
  end

  def update
    @report = NoShowReport.find(params[:id])
    if @report.update(params.require(:no_show_report).permit(:status, :operational_memo))
      redirect_to super_admin_no_show_report_path(@report), notice: '確認状況と運営メモを保存しました。'
    else
      render :show, status: :unprocessable_entity
    end
  end
end
