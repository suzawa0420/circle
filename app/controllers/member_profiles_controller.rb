class MemberProfilesController < ApplicationController
  def show
    @member = Member.includes(:prefecture).find(params[:id])
    @show_no_show_summary = NoShowReport.profile_viewable_by?(current_admin_user, webmaster: webmaster?)
    @own_no_show_reports = member_signed_in? && current_member.id == @member.id ? NoShowReport.where(conversation_id: @member.conversations.select(:id)).includes(conversation: :user).order(created_at: :desc).limit(20) : []
    if @show_no_show_summary || @own_no_show_reports.any?
      response.headers['Cache-Control'] = 'private, no-store'
      response.headers['Vary'] = 'Cookie'
    end
    @interests = @member.events.order(:order, :id)
    @review_counts = @member.received_conversation_reviews.group(:score).count
    @review_count = @review_counts.values.sum
    @reviews = @member.received_conversation_reviews.includes(conversation: :user).order(published_at: :desc).page(params[:page]).per(20)
  end
end
