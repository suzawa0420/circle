class PicteAdClicksController < ApplicationController
  skip_before_action :set_imperfect_current_user

  def create
    response.headers['Cache-Control'] = 'no-store'
    return head :unprocessable_entity unless PicteAdClickCount::PLACEMENTS.key?(params[:placement])

    PicteAdClickCount.record_click!(params[:placement])
    head :no_content
  end
end
