# frozen_string_literal: true

module RegistrationEmailVerification
  private

  def send_registration_verification(account, delivery)
    begin
      delivery.deliver_now
    rescue StandardError
      flash[:alert] = '会員登録は完了しましたが、確認メールを送信できませんでした。確認画面から再送してください。'
      return
    end

    account.update!(verification_sent_at: Time.current)
    flash[:notice] = '会員登録が完了しました。確認メールを送信しましたので、メール内のリンクから認証してください。リンクの有効期限は24時間です。'
  end
end
