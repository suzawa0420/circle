class AdminUserEmailVerificationsController < ApplicationController
  skip_before_action :set_imperfect_current_user
  before_action :authenticate_admin_user!
  before_action do
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['Referrer-Policy'] = 'same-origin'
    set_meta_tags og: { url: request.base_url + request.path }, canonical: request.base_url + request.path
  end

  def show; end

  def create
    current_admin_user.with_lock do
      if current_admin_user.email_verified?
        return redirect_to admin_user_email_verification_path, notice: 'メールアドレスは確認済みです。'
      end
      if current_admin_user.verification_sent_at && current_admin_user.verification_sent_at > 1.minute.ago
        return redirect_to admin_user_email_verification_path, alert: '少し待ってから再送してください。'
      end
      ChatMailer.verify_owner_email(current_admin_user).deliver_now
      current_admin_user.update!(verification_sent_at: Time.current)
    end
    redirect_to admin_user_email_verification_path, notice: '確認メールを送信しました。リンクの有効期限は24時間です。'
  end

  # Mail scanners may open links; only the authenticated confirmation PATCH verifies.
  def confirm
    @token = params[:token].to_s
    @valid = AdminUser.find_signed(@token, purpose: current_admin_user.email_verification_purpose) == current_admin_user
    render :confirm, status: @valid ? :ok : :unprocessable_entity
  end

  def update
    verified = false
    current_admin_user.with_lock do
      account = AdminUser.find_signed(params[:token].to_s, purpose: current_admin_user.email_verification_purpose)
      if account == current_admin_user
        current_admin_user.update!(email_verified_at: Time.current)
        verified = true
      end
    end
    unless verified
      return redirect_to admin_user_email_verification_path, alert: 'リンクが無効または期限切れです。確認メールを再送してください。'
    end
    destination = stored_location_for(:admin_user) || (current_admin_user.users.exists? ? conversations_path : new_user_path)
    redirect_to destination, notice: 'メールアドレスを確認しました。'
  end
end
