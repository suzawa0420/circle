class Unsubscribe::MembersController < Unsubscribe::ApplicationController
  before_action :require_member_login
  before_action :prevent_caching

  def show
    @member = current_member
  end

  def destroy
    @member = current_member

    unless params[:confirm_withdrawal] == '1'
      flash.now[:alert] = '削除される内容を確認し、確認欄にチェックしてください。'
      return render :show, status: :unprocessable_entity
    end

    @member.destroy!
    sign_out(:member)
    redirect_to root_path, notice: '参加者アカウントの退会が完了しました。', status: :see_other
  rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey
    flash.now[:alert] = '退会を完了できませんでした。アカウントは削除されていません。運営へお問い合わせください。'
    render :show, status: :unprocessable_entity
  end

  private

  def require_member_login
    return if member_signed_in?

    store_location_for(:member, unsubscribe_member_path)
    redirect_to new_member_session_path, alert: '退会する参加者アカウントでログインしてください。'
  end

  def prevent_caching
    response.headers['Cache-Control'] = 'private, no-store'
  end
end
