class ScheduleCheckInManagementController < ApplicationController
  before_action :private_response
  before_action :authenticate_owner_or_webmaster!
  before_action :set_schedule

  def show
    return redirect_to manage_attendance_user_schedule_path(@circle, @schedule, anchor: 'day-check-ins') if @circle.attendance_check_in_token.blank?
    render layout: 'schedule_check_in'
  end

  def create
    @circle.with_lock do
      if @circle.attendance_check_in_token.blank? || (params[:reissue] == '1' && params[:confirm_reissue] == '1')
        @circle.update_columns(attendance_check_in_token: SecureRandom.urlsafe_base64(24))
      end
    end
    redirect_to check_in_qr_user_schedule_path(@circle, @schedule), status: :see_other
  end

  def destroy
    @schedule.with_lock { @schedule.schedule_check_ins.find(params[:check_in_id]).destroy! }
    redirect_to manage_attendance_user_schedule_path(@circle, @schedule, anchor: 'day-check-ins'), status: :see_other
  end

  private

  def private_response
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['X-Robots-Tag'] = 'noindex, nofollow'
    response.headers['Referrer-Policy'] = 'no-referrer'
  end

  def set_schedule
    @circle = User.find(params[:user_id])
    return head :forbidden unless can_manage_circle?(@circle)

    @schedule = @circle.schedules.find(params[:id])
  end
end
