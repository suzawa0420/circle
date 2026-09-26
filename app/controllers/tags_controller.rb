class TagsController < ApplicationController
include ApplicationHelper

before_action :set_tags

  # def index
  #   @tag_users = @tag.user_tags.map{|t| t.user.id}

  #   # ソート機能
  #   if params[:sort] == "1" || params[:sort] == nil
  #     @users = User.tag(@tag_users).user_sort_1.page(params[:page])
  #   elsif params[:sort] == "2"
  #     @users = User.tag(@tag_users).user_sort_2.page(params[:page])
  #   else params[:sort] == "3"
  #     @users = User.tag(@tag_users).user_sort_3.page(params[:page])
  #   end

  #   # パンくず
  #   @b1_name = @tag.name
  #   @b1_url = "/tag/#{@tag.id}"

  # end

	def event
    @event = Event.find_by!(ruby: params[:ruby])

    # ソート機能
    if params[:sort] == "1" || params[:sort] == nil
      @users = User.tag(@tag_users).event(@event.id).user_sort_1.page(params[:page])
    elsif params[:sort] == "2"
      @users = User.tag(@tag_users).event(@event.id).user_sort_2.page(params[:page])
    else params[:sort] == "3"
      @users = User.tag(@tag_users).event(@event.id).user_sort_3.page(params[:page])
    end

		# パンくず
		@b1_name = @event.name
		@b1_url = "/#{@event.ruby}"
		@b2_name = @tag.name
    @b2_url = "/#{@event.ruby}/tag/#{@tag.id}"

	end

	def event_prefecture
		@event = Event.find_by!(ruby: params[:ruby])
		@prefecture = Prefecture.find_by!(kana: params[:kana])
    @cities = City.where(prefecture_id: @prefecture.id).order(:id => :asc)

    # ソート機能
    if params[:sort] == "1" || params[:sort] == nil
      @users = User.prefecture(@prefecture.id).or(User.prefecture_sub(@prefecture.id)).or(User.prefecture_50)
      .tag(@tag_users).event(@event.id).user_sort_1.page(params[:page])
    elsif params[:sort] == "2"
      @users = User.prefecture(@prefecture.id).or(User.prefecture_sub(@prefecture.id)).or(User.prefecture_50)
      .tag(@tag_users).event(@event.id).user_sort_2.page(params[:page])
    else params[:sort] == "3"
      @users = User.prefecture(@prefecture.id).or(User.prefecture_sub(@prefecture.id)).or(User.prefecture_50)
      .tag(@tag_users).event(@event.id).user_sort_3.page(params[:page])
    end

		# パンくず
		@b1_name = @event.name
		@b1_url = "/#{@event.ruby}"
		@b2_name = @prefecture.name
		@b2_url = "/#{@event.ruby}/#{@prefecture.kana}"
		@b3_name = @tag.name
    @b3_url = "/#{@event.ruby}/#{@prefecture.kana}/tag/#{@tag.id}"

	end


	def event_prefecture_city
		@event = Event.find_by!(ruby: params[:ruby])
		@city = City.find_by!(city_kana: params[:city_kana])
		@prefecture =  Prefecture.find_by!(id: @city.prefecture_id)
    @cities = City.where(prefecture_id: @prefecture.id).order(:id => :asc)
		@prefecture_judge = Prefecture.find_by!(kana: params[:kana])
		@city_users = @city.users_cities.select(:user_id)

    # ソート機能
    if params[:sort] == "1" || params[:sort] == nil
      @users = User.city(@city_users).or(User.prefecture_50)
      .tag(@tag_users).event(@event.id).user_sort_1.page(params[:page])
    elsif params[:sort] == "2"
      @users = User.city(@city_users).or(User.prefecture_50)
      .tag(@tag_users).event(@event.id).user_sort_2.page(params[:page])
    else params[:sort] == "3"
      @users = User.city(@city_users).or(User.prefecture_50)
      .tag(@tag_users).event(@event.id).user_sort_3.page(params[:page])
    end

		if @city.prefecture_id.to_i != @prefecture_judge.id.to_i
      flash[:notice] = "URLが間違っています"
      return redirect_to circles_path
		end

		# パンくず
		@b1_name = @event.name
		@b1_url = "/#{@event.ruby}"
		@b2_name = @prefecture.name
		@b2_url = "/#{@event.ruby}/#{@prefecture.kana}"
		@b3_name = @city.name
		@b3_url = "/#{@event.ruby}/#{@prefecture.kana}/#{@city.city_kana}"
		@b4_name = @tag.name
    @b4_url = "/#{@event.ruby}/#{@prefecture.kana}/#{@city.city_kana}/tag/#{@tag.id}"

	end


	def prefecture
		@prefecture = Prefecture.find_by!(kana: params[:kana])
    @cities = City.where(prefecture_id: @prefecture.id).order(:id => :asc)

    # ソート機能
    if params[:sort] == "1" || params[:sort] == nil
      @users = User.prefecture(@prefecture.id).or(User.prefecture_sub(@prefecture.id)).or(User.prefecture_50)
      .tag(@tag_users).user_sort_1.page(params[:page])
    elsif params[:sort] == "2"
      @users = User.prefecture(@prefecture.id).or(User.prefecture_sub(@prefecture.id)).or(User.prefecture_50)
      .tag(@tag_users).user_sort_2.page(params[:page])
    else params[:sort] == "3"
      @users = User.prefecture(@prefecture.id).or(User.prefecture_sub(@prefecture.id)).or(User.prefecture_50)
      .tag(@tag_users).user_sort_3.page(params[:page])
    end

		# パンくず
		@b1_name = @prefecture.name
		@b1_url = "/prefectures/#{@prefecture.kana}"
		@b2_name = @tag.name
    @b2_url = "/prefectures/#{@prefecture.kana}/tag/#{@tag.id}"

	end


	def prefecture_city
		@city = City.find_by!(city_kana: params[:city_kana])
		@prefecture =  Prefecture.find_by!(id: @city.prefecture_id)
		@cities = City.where(prefecture_id: @prefecture.id).order(:id => :asc)
		@prefecture_judge = Prefecture.find_by!(kana: params[:kana])
		@city_users = @city.users_cities.select(:user_id)

    # ソート機能
    if params[:sort] == "1" || params[:sort] == nil
      @users = User.city(@city_users).or(User.prefecture_50)
      .tag(@tag_users).user_sort_1.page(params[:page])
    elsif params[:sort] == "2"
      @users = User.city(@city_users).or(User.prefecture_50)
      .tag(@tag_users).user_sort_2.page(params[:page])
    else params[:sort] == "3"
      @users = User.city(@city_users).or(User.prefecture_50)
      .tag(@tag_users).user_sort_3.page(params[:page])
    end

		if @city.prefecture_id.to_i != @prefecture_judge.id.to_i
      flash[:notice] = "URLが間違っています"
      return redirect_to circles_path
		end

		# パンくず
		@b1_name = @prefecture.name
		@b1_url = "/prefectures/#{@prefecture.kana}"
		@b2_name = @city.name
		@b2_url = "/prefectures/#{@prefecture.kana}/#{@city.city_kana}"
		@b3_name = @tag.name
    @b3_url = "/prefectures/#{@prefecture.kana}/#{@city.city_kana}/tag/#{@tag.id}"

	end


private
	def set_tags
		@tag = Tag.find(params[:id])
    @categories = Category.all.order(:id => :asc)
		@events = Event.all.where.not(id: 0).order(:order => :asc)
		@prefectures = Prefecture.all.order(:order => :asc).where.not(id: 0)
    @cities = City.all.order(:id => :asc)
		@ages = Age.all
		@groups = Group.all.order(:id => :asc)
		@schedules = Schedule.where("day > ?", DateTime.yesterday).order(:day => :asc)
    @tags = Tag.all.order(:order => :asc)
    # Keep membership filtering in SQL; loading each associated User is N+1.
    @tag_users = @tag.user_tags.select(:user_id)

    @search_word = "例）バスケ　東京"

		if admin_user_signed_in?
			@admin_user = current_admin_user
			@user = @admin_user.users.first
		end

	end


	def tag_params
		params.require(:user).permit(
			:name, :category, :tag, :name, :text, :order
    )
	end


end
