# frozen_string_literal: true

module ScheduleDecorator

  def ogp_img
    if top_image.present?
      self.top_image.url
    else
      default_ogp_image_url
    end
  end

end
