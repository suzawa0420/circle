class SuperAdmin::ReviewsController < ApplicationController
  before_action :require_webmaster!

  def index
    @place_reviews = PlaceReview.includes(:place).order(created_at: :desc).page(params[:place_page]).per(30)
    @reviews = Review.includes(:user, :member, :conversation_review).order(created_at: :desc).page(params[:page]).per(30)
    @evaluations = ConversationReview.publicly_visible.where(author_role: 'owner').includes(conversation: [:user, :member]).order(published_at: :desc).page(params[:evaluation_page]).per(30)
  end

  def destroy_evaluation
    evaluation = ConversationReview.publicly_visible.find(params[:id])
    evaluation.conversation.delete_review!(evaluation.author_role)
    redirect_to super_admin_reviews_path, notice: '口コミを削除しました。相手側の口コミには影響しません。'
  end
end
