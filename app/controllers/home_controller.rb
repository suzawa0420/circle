class HomeController < ApplicationController
  def index
    @categories = Category.all.order(order: :asc)
    @prefectures = Prefecture.all.order(order: :asc)
    @users = User.publicly_visible.includes([:event, :prefecture]).order(switch: :asc, last_post: :desc).limit(6)

    @match_events = Event.where(matching: 1).order(:order => :asc)
		@place_events = Event.where(place: 1).order(:order => :asc)
    @match_users = Match.where(recruit: "募集中", user_id: User.publicly_visible.select(:id)).includes(user: [:event, :prefecture]).order(updated_at: "DESC").limit(6)
  end
end
