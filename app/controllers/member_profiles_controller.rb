class MemberProfilesController < ApplicationController
  def show
    @member = Member.includes(:prefecture).find(params[:id])
    @interests = @member.events.order(:order, :id)
    @review_counts = @member.received_conversation_reviews.group(:score).count
    @review_count = @review_counts.values.sum
    @reviews = @member.received_conversation_reviews.includes(conversation: :user).order(published_at: :desc).page(params[:page]).per(20)
  end
end
