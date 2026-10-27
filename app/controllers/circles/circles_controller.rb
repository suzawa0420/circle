class Circles::CirclesController < Circles::ApplicationController
  before_action :set_search, only: [:index, :search]

	def index
    users = User.list.includes(:schedules, :prefecture_sub)
    case params[:sort]
    when "1", nil
      @users = users.sort_1.page(params[:page])
    when "2"
      @users = users.sort_2.page(params[:page])
    when "3"
      @users = users.sort_3.page(params[:page])
    end

  end


	def show
		@user = User.find(params[:id])
		unless @user.publicly_visible?
			raise ActiveRecord::RecordNotFound unless can_manage_circle?(@user)
			set_meta_tags noindex: true
		end
		@sub_prefecture = Prefecture.find_by(id: @user.prefecture_sub_id)
		@schedules = @user.publicly_visible? ? CircleUpcomingActivities.from(@user.schedules
      .where('day >= ?', Time.current.in_time_zone('Tokyo').to_date.iso8601)
      .select(:id, :user_id, :day, :time_s, :time_e, :venue, :recruitment)) : []
		@questions = Question.where(user_id: @user.id).order(created_at: "DESC")

    @admin_user = AdminUser.find(@user.admin_user.id)

    @user_cities = @user.users_cities.includes([city: :prefecture]).map{|c| c.city}
    @user_groups = @user.users_groups.includes([:group]).map{|g| g.group}
		@user_ages = @user.users_ages.includes([:age]).map{|a| a.age}

		@users = User.publicly_visible.where.not(id: @user.id).prefecture(@user.prefecture_id).event(@user.event_id).where(switch: "募集中").order(:last_post => :desc).moderation_last.limit(3)
  end


end
