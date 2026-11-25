# frozen_string_literal: true

module AccountPasswordRecovery
  include AccountEmailDelivery

  RESET_NOTICE = '入力したメールアドレスがこのアカウント種別に登録されている場合は、再設定メールをお送りします。届かない場合は、入力内容・主催者と参加者の区分・迷惑メールフォルダをご確認ください。'.freeze

  def create
    email = resource_params[:email].to_s.strip

    unless email.bytesize <= 254 && URI::MailTo::EMAIL_REGEXP.match?(email)
      self.resource = resource_class.new(email: email)
      resource.errors.add(:base, 'メールアドレスの形式を確認してください。')
      return render :new, status: :unprocessable_content
    end

    begin
      resource_class.send_reset_password_instructions(email: email)
    rescue *AccountEmailDelivery::DELIVERY_ERRORS => error
      log_account_email_failure(:password_reset, resource_name, error)
    end

    # Do not let the reset endpoint disclose whether an account exists.
    redirect_to new_password_path(resource_name), notice: RESET_NOTICE, status: :see_other
  end
end
