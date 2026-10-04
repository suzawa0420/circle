class SuperAdmin::OpinionsController < ApplicationController
  before_action :require_webmaster!

  def index
    @opinions = Opinion.includes(:user).order(created_at: :desc, id: :desc).page(params[:page]).per(30)
  end
end
