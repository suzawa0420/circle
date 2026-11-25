# frozen_string_literal: true

module AccountPasswordRecovery
  include AccountEmailDelivery

  def create
    super
  rescue *AccountEmailDelivery::DELIVERY_ERRORS => error
    log_account_email_failure(:password_reset, resource_name, error)
    redirect_to new_password_path(resource_name),
      alert: '再設定メールを送信できませんでした。時間をおいて再度お試しください。',
      status: :see_other
  end
end
