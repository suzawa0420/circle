class Webmasters::DashboardController < ApplicationController
  before_action :require_webmaster!

  def index
    @pending_support_requests = SupportRequest.where(status: 'pending').where.not(kind: 'suggestion').count
    @pending_suggestions = SupportRequest.where(kind: 'suggestion', status: 'pending').count
    @pending_reports = ChatReport.where(resolved_at: nil).count
    @pending_circles = User.where(moderation_status: 'review').count
    @pending_blogs = Blog.where(moderation_status: 'review').count
    @pending_place_reviews = PlaceReview.where(moderation_status: 'review').count
  end
end
