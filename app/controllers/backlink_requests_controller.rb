class BacklinkRequestsController < ApplicationController
  before_action :authenticate_owner_or_webmaster!
  before_action :set_circle

  def show
    @backlink_request = BacklinkRequest.find_by(user: @user) || BacklinkRequest.new
  end

  def create
    @backlink_request = BacklinkRequest.submit!(@user, params.require(:backlink_request).permit(:placement_url)[:placement_url]) do |request|
      BacklinkRequestMailer.submitted(request).deliver_later
    end
    redirect_to circle_backlink_request_path(@user), notice: '申請状況をご確認ください。運営が掲載内容を確認します。'
  rescue ActiveRecord::RecordInvalid => e
    @backlink_request = e.record
    @backlink_request.status = @backlink_request.status_in_database || 'pending'
    render :show, status: :unprocessable_entity
  end

  private

  def set_circle
    @user = User.find(params[:circle_id])
    head :forbidden unless can_manage_circle?(@user)
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['X-Robots-Tag'] = 'noindex, nofollow'
  end
end
