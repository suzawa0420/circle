class SuperAdmin::OpinionsController < ApplicationController
  before_action :require_webmaster!

  def index
    @suggestions = SupportRequest.where(kind: 'suggestion').order(created_at: :desc, id: :desc).page(params[:suggestion_page]).per(30)
    @opinions = Opinion.includes(:user).order(created_at: :desc, id: :desc).page(params[:page]).per(30)
  end
end
