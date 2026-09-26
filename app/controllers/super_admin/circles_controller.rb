class SuperAdmin::CirclesController < ApplicationController
  before_action :authenticate_admin_user!
  before_action :require_super_admin

  def index
    @admin_users = AdminUser.order(created_at: :desc).includes(:users).page(params[:page]).per(50)
    @review_circles = User.where(moderation_status: "review").order(updated_at: :desc).limit(50)
    @review_blogs = Blog.where(moderation_status: "review").includes(:user).order(updated_at: :desc).limit(50)
    @review_place_reviews = PlaceReview.where(moderation_status: "review").includes(:place).order(created_at: :desc).page(params[:review_page]).per(30)
    @blocked_circles = User.where(moderation_status: "blocked").order(updated_at: :desc).limit(50)
    @blocked_blogs = Blog.where(moderation_status: "blocked").includes(:user).order(updated_at: :desc).limit(50)
  end

  def destroy
    @admin_user = AdminUser.find(params[:id])
    @admin_user.destroy
    flash[:notice] = "削除しました"
    redirect_to super_admin_circles_path
  end

  private

  def require_super_admin
    unless current_admin_user.super_admin?
      flash[:notice] = "権限がありません"
      redirect_to root_path
    end
  end
end
