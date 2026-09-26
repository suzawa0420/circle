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
			raise ActiveRecord::RecordNotFound unless admin_user_signed_in? && (current_admin_user.master_account? || current_admin_user.id == @user.admin_user_id)
			set_meta_tags noindex: true
		end
		@sub_prefecture = Prefecture.find_by(id: @user.prefecture_sub_id)
		@schedules = Schedule.where(user_id: @user.id).where("day > ?", DateTime.yesterday).order(:day => :asc)
		@questions = Question.where(user_id: @user.id).where.not(answer: nil).order(created_at: "DESC")

    @admin_user = AdminUser.find(@user.admin_user.id)

    @user_cities = @user.users_cities.includes([city: :prefecture]).map{|c| c.city}
    @user_groups = @user.users_groups.includes([:group]).map{|g| g.group}
		@user_ages = @user.users_ages.includes([:age]).map{|a| a.age}

		@users = User.publicly_visible.where.not(id: @user.id).prefecture(@user.prefecture_id).event(@user.event_id).where(switch: "募集中").order(:last_post => :desc).limit(5)
  end


end
