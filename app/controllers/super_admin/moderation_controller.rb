class SuperAdmin::ModerationController < ApplicationController
  before_action :require_webmaster!
  before_action :require_super_admin

  def circle
    user = User.find(params[:id])
    status = moderation_status
    user.with_lock do
      if status == 'clear' && user.moderation_reasons.any? { |reason| CircleProfilePolicy::FINGERPRINTED_REASONS.include?(reason['code']) }
        unless ActiveSupport::SecurityUtils.secure_compare(params[:profile_fingerprint].to_s, CircleProfilePolicy.solicitation_fingerprint(user))
          redirect_to super_admin_circles_path, alert: '表示後に募集内容が変更されました。最新の内容を確認してから、もう一度承認してください。'
          return
        end
      end
      attributes = { moderation_status: status }
      # Legacy review entries may have no saved reasons. Remember what was
      # accepted so subsequent edits do not send them back to the review queue.
      if status == 'clear'
        if user.moderation_reasons.empty?
          attributes[:moderation_reasons] = user.moderation_snapshot
        elsif user.moderation_reasons.any? { |reason| CircleProfilePolicy::FINGERPRINTED_REASONS.include?(reason['code']) }
          # Approve the content actually reviewed, including edits made while held.
          attributes[:moderation_reasons] = user.moderation_reasons.reject { |reason| CircleProfilePolicy::FINGERPRINTED_REASONS.include?(reason['code']) } +
            user.moderation_snapshot.select { |reason| CircleProfilePolicy::FINGERPRINTED_REASONS.include?(reason['code']) }
        end
        attributes[:moderation_checked_at] = user.moderation_checked_at || Time.current
      elsif status == 'review' && user.moderation_rule_reasons.any?
        attributes[:moderation_reasons] = user.moderation_snapshot
        attributes[:moderation_checked_at] = Time.current
      end
      user.update_columns(attributes)
    end
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
