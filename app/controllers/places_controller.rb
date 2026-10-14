class PlacesController < ApplicationController
  include ApplicationHelper

	before_action :require_webmaster!, only: [:new, :create, :count, :destroy]
	before_action :ensure_correct_user, {only: [:edit, :update]}
	before_action :set_place, {only: [:event, :prefecture, :city, :show, :search]}

  def index
    prepare_place_filters
    @places = place_listing.order(updated_at: :desc, id: :desc).page(params[:page])
    @places_count = Place.count
  end

  def global_search
    prepare_place_filters
    @selected_event = @events.find { |event| event.ruby == params[:sport] }
    @selected_prefecture = @prefectures.find { |prefecture| prefecture.kana == params[:area] }
    raise ActiveRecord::RecordNotFound if params[:sport].present? && !@selected_event
    raise ActiveRecord::RecordNotFound if params[:area].present? && !@selected_prefecture
    set_meta_tags noindex: true
    places = place_listing
    places = places.where(id: PlacesEvent.where(event_id: @selected_event.id).select(:place_id)) if @selected_event
    places = places.where(prefecture_id: @selected_prefecture.id) if @selected_prefecture
    @places = filter_place_keywords(places).order(updated_at: :desc, id: :desc).page(params[:page])
    @places_count = @places.total_count
    render :index
  end

  def search
    return redirect_to("/places/#{@event.ruby}") if place_keywords.empty?

    @places = filter_place_keywords(place_listing.where(id: @event_places))
      .order(updated_at: :desc, id: :desc).page(params[:page])
    @places_count = @places.total_count
    DbSearch.create(keyword: params[:kw])
  end


	def new
		@place = Place.new
		@place_button = "登録する"
	end

	def create
    @place = Place.new(place_params)
    if admin_user_signed_in?
      @current_user = User.find_by(admin_user_id: current_admin_user.id)
    end
		@place.user_id = @current_user&.id

    if @place.save(place_params)
			@prefecture = Prefecture.find_by(id: @place.prefecture_id)
			@city = City.find_by(id: @place.city_id)
			flash[:notice] = '登録完了！'
			redirect_to "/places/all/#{@prefecture.kana}/#{@city.city_kana}/#{@place.id}"
		else
			render "/places/edit"
		end
	end


	def show
		@place = Place.find(params[:id])
		@prefecture = Prefecture.find_by!(kana: params[:kana])
		@city = @prefecture.cities.find_by!(city_kana: params[:city_kana])

    @places = place_listing.where(id: @event_places, prefecture_id: @prefecture.id, city_id: @city.id).where.not(id: @place.id).order(updated_at: :desc, id: :desc).limit(5)
    @users = User.publicly_visible.where(event_id: @event.id, prefecture_id: @prefecture.id, switch: "募集中").order(switch: :asc, last_post: :desc).limit(3)
    @place_events = @place.events.to_a

    @place_events.each do |event|
			if event.id == @event.id
				@place_event_id = event.id
			end
		end

    @place_review = @place.place_reviews.build
    @place_reviews = @place.public_place_reviews
    @ip = PlaceReview.where(place_id: @place.id, ip_address: request.remote_ip)


		if @event.id.to_i != @place_event_id.to_i || @prefecture.id.to_i != @place.prefecture_id.to_i || @city.id.to_i != @place.city_id.to_i
			flash[:notice] = 'URLが間違っています'
			redirect_to "/places"
		end

		@b2_name = @event.name
		@b2_url = "/places/#{@event.ruby}"
		@b3_name = @prefecture.name
		@b3_url = "/places/#{@event.ruby}/#{@prefecture.kana}"
		@b4_name = @city.name
		@b4_url = "/places/#{@event.ruby}/#{@prefecture.kana}/#{@city.city_kana}"
		@b5_name = @place.name
    @b5_url = "/places/#{@event.ruby}/#{@prefecture.kana}/#{@city.city_kana}/#{@place.id}"

	end

	def no_index
    @places = Place.all
  end


	def show_noindex
		@place = Place.find(params[:id])
		@prefecture = Prefecture.find_by!(kana: params[:kana])
		@city = @prefecture.cities.find_by!(city_kana: params[:city_kana])
		@place_events = @place.places_events.map{|e| e.event}

    if admin_user_signed_in?
      @current_user = User.find_by(admin_user_id: current_admin_user.id)
    end
	end

	def edit
		@place = Place.find(params[:id])
		@place_button = "更新する"
	end

	def update
		@place = Place.find(params[:id])
		@prefecture = Prefecture.find_by(id: @place.prefecture_id)
		@city = City.find_by(id: @place.city_id)

		if @place.update(place_params)
			flash[:notice] = '更新完了！'
			redirect_to "/places/all/#{@prefecture.kana}/#{@city.city_kana}/#{@place.id}"
		else
			render "/places/edit"
		end
	end

	def destroy
    @place = Place.find(params[:id])
    @place.destroy
		flash[:notice] = '削除しました！'
		redirect_to "/places"
	end

	def count
    @places = Place.group(:user_id).count(:user_id)
	end

	def event
    @places = place_listing.where(id: @event_places).order(updated_at: "DESC").page(params[:page])
    @places_count = Place.where(id: @event_places).count
    @b2_name = @event.name
    @b2_url = "/places/#{@event.ruby}"

	end

	def prefecture
		@prefecture = Prefecture.find_by!(kana: params[:kana])
		@cities = City.where(prefecture_id: @prefecture.id).order(places_count: "DESC")
    @places = place_listing.where(id: @event_places).where(prefecture_id: @prefecture.id).order(updated_at: "DESC").page(params[:page])
    @places_count = Place.where(id: @event_places).where(prefecture_id: @prefecture.id).count
		@b2_name = @event.name
		@b2_url = "/places/#{@event.ruby}"
		@b3_name = @prefecture.name
    @b3_url = "/places/#{@event.ruby}/#{@prefecture.kana}"

	end

	def city
		@prefecture = Prefecture.find_by!(kana: params[:kana])
		@city = @prefecture.cities.find_by!(city_kana: params[:city_kana])
    @places = place_listing.where(id: @event_places).where(prefecture_id: @prefecture.id).where(city_id: @city.id).order(updated_at: "DESC").page(params[:page])
    @places_count = Place.where(id: @event_places).where(prefecture_id: @prefecture.id).where(city_id: @city.id).count
		@b2_name = @event.name
		@b2_url = "/places/#{@event.ruby}"
		@b3_name = @prefecture.name
		@b3_url = "/places/#{@event.ruby}/#{@prefecture.kana}"
		@b4_name = @city.name
    @b4_url = "/places/#{@event.ruby}/#{@prefecture.kana}/#{@city.city_kana}"

	end

	private
  def prepare_place_filters
    @events = Event.where(place: 1).order(order: :asc)
    @prefectures = Prefecture.where.not(id: 50).order(order: :asc)
    @b1_name = "体育館・コート情報"
    @b1_url = "/places"
  end

  def place_listing
    Place.includes(:prefecture, :city, :events)
  end

  def place_keywords
    (params[:kw].is_a?(String) ? params[:kw] : '').split(/[[:space:]]+/).select(&:present?)
  end

  def filter_place_keywords(places)
    place_keywords.each do |keyword|
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(keyword)}%"
      matches = Place.place_search_word(keyword)
        .or(Place.where(id: PlacesEvent.where(event_id: Event.where("name LIKE ?", pattern).select(:id)).select(:place_id)))
        .or(Place.where(prefecture_id: Prefecture.where("name LIKE ?", pattern).select(:id)))
        .or(Place.where(city_id: City.where("name LIKE ?", pattern).select(:id)))
      places = places.where(id: matches.select(:id))
    end
    places
  end

	def correct_user
    if webmaster?
    else
        flash[:notice] = "権限がありません"
        redirect_to "/places"
    end
  end

	def ensure_correct_user
    return if webmaster?
		@place = Place.find(params[:id])
		@user = User.find_by(id: @place.user_id)
    if current_admin_user.id != @user.admin_user_id.to_i
      if webmaster?
      else
        flash[:notice] = "権限がありません"
        redirect_to "/places"
      end
    end
	end

  def set_place
    @events = Event.all
    @event = Event.find_by!(ruby: params[:ruby])
    @prefectures = Prefecture.where.not(id: 50).order(:order => :asc)
    @event_ids = PlacesEvent.where(event_id: @event.id)
    @event_places = @event_ids.map { |e| e.place_id }
    @search_word = "例）サークルブック体育館"
    @b1_name = "体育館・コート情報"
    @b1_url = "/places"
    if admin_user_signed_in?
      @current_user = User.find_by(admin_user_id: current_admin_user.id)
    end
  end

	def place_params
		params.require(:place).permit(
			:user_id,
			:prefecture_id,
			:city_id,
			:event_id,
			:name,
			:address,
			:access,
			:parking,
			:time,
			:regular_holiday,
			:scale,
			:price,
			:tel,
			:url,
			:tag,
			:sns,
			:img_link,
			:img_url,
			:img_source,
      :average_facility,
      :average_reservation,
      :average_price,
      :average_access,
      :average_score,
			event_ids:[]
		)
	end


end
