class DbValidationErrorsController < ApplicationController
  before_action :webmaster

  def index
    @db_validation_errors = DbValidationError.all.order(id: "DESC").page(params[:page])
  end

  private
  def webmaster
    require_webmaster!
  end

end
