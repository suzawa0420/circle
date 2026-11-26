class HomeController < ApplicationController
  PREVIEW_LIMIT = 3

  def index
    @listing_data = CircleListingData.new(PublicListingPreview.call(User.publicly_visible.sort_2, limit: PREVIEW_LIMIT))
    @users = @listing_data.users
    @day_listing = EventDayListing.new(date: Date.current)
    @schedules = @day_listing.schedules.limit(PREVIEW_LIMIT)
  end
end
