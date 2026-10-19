# frozen_string_literal: true

module ScheduleDecorator

  def ogp_img
    ogp_user_schedule_url(user_id, id, format: :png, v: ScheduleOgpImage.version_for(self))
  end

end
