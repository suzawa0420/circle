class HomeController < ApplicationController
  def index
    @listing_data = CircleListingData.new(User.publicly_visible.sort_1.limit(5))
    @users = @listing_data.users
    @day_listing = EventDayListing.new(date: Date.current)
    @schedules = @day_listing.schedules.limit(5)
    @blogs = Blog.publicly_visible.preload(user: [:event, :prefecture]).order(updated_at: :desc, id: :desc).limit(5)
    @matches = Match.where(recruit: "募集中", user_id: User.publicly_visible.select(:id))
      .preload(user: [:event, :prefecture]).order(updated_at: :desc, id: :desc).limit(5)
    @places = Place.joins(:prefecture, :city, :events).distinct
      .preload(:prefecture, :city, :events).order(updated_at: :desc, id: :desc).limit(6)
    @place_review_counts = PlaceReview.where(moderation_status: "clear", place_id: @places.map(&:id)).group(:place_id).count
  end
end
