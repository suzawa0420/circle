class SuperAdmin::PicteAdClicksController < ApplicationController
  before_action :require_webmaster!

  def index
    @today = Time.current.in_time_zone('Tokyo').to_date
    @totals = PicteAdClickCount.group(:placement).sum(:click_count)
    @daily = PicteAdClickCount.where(recorded_on: (@today - 29)..@today).group(:recorded_on, :placement).sum(:click_count)
  end
end
