class HomeController < ApplicationController
  def index
    @listing_data = CircleListingData.new(User.publicly_visible.sort_2.limit(5))
    @users = @listing_data.users
    @day_listing = EventDayListing.new(date: Date.current)
    @schedules = @day_listing.schedules.limit(5)
    @blogs = Blog.publicly_visible.where("COALESCE(image_01, '') <> '' OR COALESCE(image_02, '') <> '' OR COALESCE(image_03, '') <> '' OR COALESCE(image_04, '') <> ''").preload(user: [:event, :prefecture]).order(updated_at: :desc, id: :desc).moderation_last.limit(5)
    @matches = Match.where(recruit: "募集中", user_id: User.publicly_visible.select(:id))
      .preload(user: [:event, :prefecture]).order(updated_at: :desc, id: :desc).moderation_last.limit(5)
    @places = Place.joins(:prefecture, :city, :events).distinct
      .preload(:prefecture, :city, :events).order(updated_at: :desc, id: :desc).limit(6)
  end
end
