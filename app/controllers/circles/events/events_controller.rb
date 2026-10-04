class Circles::Events::EventsController < Circles::Events::ApplicationController
  before_action :set_search, only: [:show]

	def index
    redirect_to circles_path, status: 301
  end


  def show
		@event = Event.find_by!(ruby: params[:kana])

    users = User.where(event_id: @event.id).list
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