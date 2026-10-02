class SuperAdmin::PlacesController < ApplicationController
  before_action :require_webmaster!

  def index
    @places = Place.order(id: :desc).page(params[:page]).per(50)
  end
end
