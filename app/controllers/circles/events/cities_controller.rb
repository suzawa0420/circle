class Circles::Events::CitiesController < Circles::Events::ApplicationController
  before_action :set_search, only: [:show]

	def index
    redirect_to event_prefecture_path(params[:event_kana], params[:prefecture_kana]), status: 301
  end

  def show
		@event = Event.find_by(ruby: params[:event_kana])
		@prefecture = Prefecture.find_by(kana: params[:prefecture_kana])
    @city = City.find_by(city_kana: params[:kana])

    return redirect_to circles_path if @event.nil? || @prefecture.nil? || @city.nil?

    users = User.where(event_id: @event.id).where_city(@city).list.order("prefectures.sort asc")

    case params[:sort]
    when "1", nil
      @users = users.sort_1.page(params[:page])
    when "2"
      @users = users.sort_2.page(params[:page])
    when "3"
      @users = users.sort_3.page(params[:page])
    end

  end



end