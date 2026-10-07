class SuperAdmin::BulkOwnerDeletionsController < ApplicationController
  before_action :require_webmaster!

  MAX_OWNERS = 50
  PURPOSE = 'bulk_owner_deletion'.freeze

  def create
    ids = params[:owner_ids]
    unless ids.is_a?(Array) && ids.size.between?(1, 150) && ids.all? { |id| id.to_s.match?(/\A[1-9]\d*\z/) }
      return invalid_selection
    end
    ids = ids.map(&:to_i).uniq.sort
    return invalid_selection if ids.size > MAX_OWNERS

    @owners = AdminUser.where(id: ids).includes(:users).order(:id).to_a
    return invalid_selection unless @owners.size == ids.size

    circles = User.where(admin_user_id: ids)
    conversations = Conversation.where(user_id: circles.select(:id))
    @impact = { circles: circles.count, conversations: conversations.count,
                messages: ChatMessage.where(conversation_id: conversations.select(:id)).count,
                reviews: Review.where(user_id: circles.select(:id)).count }
    @confirmation = verifier.generate(ids, purpose: PURPOSE, expires_in: 15.minutes)
    render :confirm
  end

  def destroy
    ids = verifier.verified(params[:confirmation].to_s, purpose: PURPOSE)
    return invalid_selection unless ids.is_a?(Array) && ids.size.between?(1, MAX_OWNERS)

    AdminUser.transaction do
      owners = AdminUser.where(id: ids).order(:id).lock.to_a
      raise ActiveRecord::RecordNotFound unless owners.size == ids.size
      owners.each(&:destroy!)
    end
    redirect_to super_admin_circles_path, notice: "主催者#{ids.size}件と関連データを削除しました。", status: :see_other
  rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordNotDestroyed, ActiveRecord::RecordInvalid, ActiveRecord::InvalidForeignKey
    redirect_to super_admin_circles_path, alert: '一括削除できませんでした。対象を選び直してやり直してください。', status: :see_other
  end

  private

  def verifier
    Rails.application.message_verifier(PURPOSE)
  end

  def invalid_selection
    redirect_to super_admin_circles_path, alert: '主催者を1〜50件選択し、確認画面から操作してください。確認の有効期限は15分です。', status: :see_other
  end
end
