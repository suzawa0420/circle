class ScheduleCheckInManagementController < ApplicationController
  before_action :private_response
  before_action :authenticate_owner_or_webmaster!
  before_action :set_scope

  def show
    render layout: 'schedule_check_in'
  end

  def create
    @circle.with_lock do
      if @circle.attendance_check_in_token.blank? || (params[:reissue] == '1' && params[:confirm_reissue] == '1')
        @circle.update_columns(attendance_check_in_token: SecureRandom.urlsafe_base64(24))
      end
    end
    redirect_to check_in_manage_path, status: :see_other
  end

  def record_usage
    return head :not_found unless @schedule && @circle.attendance_check_in_token.present?

    @schedule.with_lock do
      return head :not_found unless @schedule.day == ScheduleCheckIn.today && @schedule.recruitment != '中止'

      @schedule.record_check_in_usage!
    end
    redirect_to manage_attendance_user_schedule_path(@circle, @schedule, anchor: 'day-check-ins'), status: :see_other
  end

  def destroy
    @schedule.with_lock { @schedule.schedule_check_ins.find(params[:check_in_id]).destroy! }
    redirect_to manage_attendance_user_schedule_path(@circle, @schedule, anchor: 'day-check-ins'), status: :see_other
  end

  helper_method :check_in_manage_path, :check_in_issue_path, :check_in_back_path

  private

  def check_in_manage_path
    @schedule ? check_in_qr_user_schedule_path(@circle, @schedule) : user_check_in_qr_path(@circle)
  end

  def check_in_issue_path
    @schedule ? enable_check_in_user_schedule_path(@circle, @schedule) : user_check_in_qr_path(@circle)
  end

  def check_in_back_path
    return manage_attendance_user_schedule_path(@circle, @schedule, anchor: 'day-check-ins') if @schedule

    @circle.unique_id.present? ? attendances_path(@circle.unique_id) : user_schedules_path(@circle)
  end

  def private_response
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['X-Robots-Tag'] = 'noindex, nofollow'
    response.headers['Referrer-Policy'] = 'strict-origin'
  end

  def set_scope
    @circle = User.find(params[:user_id])
    if request.path_parameters[:id].present?
      return head :forbidden unless can_manage_circle?(@circle)

      @schedule = @circle.schedules.find(params[:id])
    else
      return head :forbidden unless admin_user_signed_in? && current_admin_user.id == @circle.admin_user_id
    end
  end
end
