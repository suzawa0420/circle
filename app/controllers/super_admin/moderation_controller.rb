class SuperAdmin::ModerationController < ApplicationController
  before_action :authenticate_admin_user!
  before_action :require_super_admin

  def circle
    user = User.find(params[:id])
    user.update_column(:moderation_status, moderation_status)
    redirect_to super_admin_circles_path, notice: "サークルの確認状態を更新しました"
  end

  def blog
    blog = Blog.find(params[:id])
    blog.update_column(:moderation_status, moderation_status)
    redirect_to super_admin_circles_path, notice: "ブログの確認状態を更新しました"
  end

  private

  def moderation_status
    status = params.require(:moderation_status)
    raise ActionController::BadRequest unless %w(clear review blocked).include?(status)

    status
  end

  def require_super_admin
    raise ActiveRecord::RecordNotFound unless current_admin_user.master_account?
  end
end
