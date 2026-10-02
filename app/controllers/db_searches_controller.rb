class DbSearchesController < ApplicationController
  before_action :webmaster

  def index
    @db_searches = DbSearch.all.order(id: "DESC").page(params[:page])
  end

  private
  def webmaster
    require_webmaster!
  end

end
