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
end
