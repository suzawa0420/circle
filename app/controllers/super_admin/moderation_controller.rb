class SuperAdmin::ModerationController < ApplicationController
  before_action :require_webmaster!
  before_action :require_super_admin

  def circle
    user = User.find(params[:id])
    status = moderation_status
    attributes = { moderation_status: status }
    # Legacy review entries may have no saved reasons. Remember what was
    # accepted so subsequent edits do not send them back to the review queue.
    if status == 'clear'
      if user.moderation_reasons.empty?
        attributes[:moderation_reasons] = ModerationReasonReport.snapshot(user.moderation_rule_reasons)
      end
      attributes[:moderation_checked_at] = user.moderation_checked_at || Time.current
    end
    user.update_columns(attributes)
    redirect_to super_admin_circles_path, notice: "サークルの確認状態を更新しました"
  end

  def blog
    blog = Blog.find(params[:id])
    blog.update_column(:moderation_status, moderation_status)
    redirect_to super_admin_circles_path, notice: "ブログの確認状態を更新しました"
  end

  def place_review
    review = PlaceReview.find(params[:id])
    review.place.with_lock do
      review.update_column(:moderation_status, moderation_status)
      review.place.refresh_review_scores!
    end
    redirect_to super_admin_circles_path, notice: "施設口コミの確認状態を更新しました"
  end

  private

  def moderation_status
    status = params.require(:moderation_status)
    raise ActionController::BadRequest unless %w(clear review blocked).include?(status)

    status
  end

  def require_super_admin
    raise ActiveRecord::RecordNotFound unless webmaster?
  end
end
