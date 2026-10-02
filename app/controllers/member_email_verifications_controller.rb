class MemberEmailVerificationsController < ApplicationController
  before_action :authenticate_member!
  before_action do
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['Referrer-Policy'] = 'same-origin'
    set_meta_tags og: { url: request.base_url + request.path }, canonical: request.base_url + request.path
  end

  def show; end

  def create
    current_member.with_lock do
      if current_member.verification_sent_at && current_member.verification_sent_at > 1.minute.ago
        return redirect_to member_email_verification_path, alert: '少し待ってから再送してください。'
      end
      ChatMailer.verify_email(current_member).deliver_now
      current_member.update!(verification_sent_at: Time.current)
    end
    redirect_to member_email_verification_path, notice: '確認メールを送信しました。リンクの有効期限は24時間です。'
  end

  # A GET only presents the confirmation form; mail scanners must not verify an account.
  def confirm
    @token = params[:token].to_s
    @valid = Member.find_signed(@token, purpose: current_member.email_verification_purpose) == current_member
    render :confirm, status: @valid ? :ok : :unprocessable_entity
  end

  def update
    verified = Member.find_signed(params[:token].to_s, purpose: current_member.email_verification_purpose)
    unless verified == current_member
      return redirect_to member_email_verification_path, alert: 'リンクが無効または期限切れです。確認メールを再送してください。'
    end
    current_member.update!(email_verified_at: Time.current)
    redirect_to stored_location_for(:member) || conversations_path, notice: 'メールアドレスを確認しました。'
  end
end
