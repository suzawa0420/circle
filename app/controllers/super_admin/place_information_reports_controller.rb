class SuperAdmin::PlaceInformationReportsController < ApplicationController
  before_action :require_webmaster!

  def index
    @status = PlaceInformationReport::STATUSES.key?(params[:status]) ? params[:status] : 'pending'
    @reports = PlaceInformationReport.includes(:place).where(status: @status).order(created_at: :asc, id: :asc).page(params[:page]).per(30)
  end

  def show
    @report = PlaceInformationReport.includes(place: [:prefecture, :city, :events]).find(params[:id])
  end

  def update
    @report = PlaceInformationReport.find(params[:id])
    @report.assign_attributes(params.require(:place_information_report).permit(:status, :staff_note))
    @report.reviewed_by = current_webmaster
    @report.reviewed_at = Time.current
    @report.resolved_at = @report.status.in?(%w[resolved dismissed]) ? Time.current : nil
    if @report.save
      redirect_to super_admin_place_information_report_path(@report), notice: '対応状況を保存しました。'
    else
      render :show, status: :unprocessable_entity
    end
  end
end
