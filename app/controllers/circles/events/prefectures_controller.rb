class Circles::Events::PrefecturesController < Circles::Events::ApplicationController
  before_action :set_search, only: [:show]

	def index
    redirect_to event_path(params[:event_kana]), status: 301
  end

  def show
		@event = Event.find_by!(ruby: params[:event_kana])
		@prefecture = Prefecture.find_by!(kana: params[:kana])


    users = User.where(event_id: @event.id).where_pref(@prefecture.id).list.order("prefectures.sort asc")
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