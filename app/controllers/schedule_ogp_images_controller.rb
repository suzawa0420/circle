# frozen_string_literal: true

# Image requests do not need page navigation, session state or attendance data.
class ScheduleOgpImagesController < ActionController::Base
  def show
    circle = User.publicly_visible.find(params[:user_id])
    schedule = circle.schedules.select(:id, :user_id, :title, :day, :time_s,
      :time_e, :venue, :top_image, :updated_at).find(params[:id])
    schedule.user = circle
    return unless stale?(etag: ScheduleOgpImage.version_for(schedule), public: true)

    expires_in 1.hour, public: true
    response.headers['X-Content-Type-Options'] = 'nosniff'
    send_data ScheduleOgpImage.new(schedule).png, type: 'image/png', disposition: 'inline'
  end
end
