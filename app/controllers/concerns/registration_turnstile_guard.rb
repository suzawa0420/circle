# frozen_string_literal: true

module RegistrationTurnstileGuard
  extend ActiveSupport::Concern

  included do
    before_action :prevent_registration_caching, only: [:new, :create]
    before_action :verify_registration_turnstile, only: :create
  end

  private

  def prevent_registration_caching
    response.headers['Cache-Control'] = 'no-store'
  end

  def verify_registration_turnstile
    result = RegistrationTurnstile.verify(params['cf-turnstile-response'])
    return if result == :accepted

    message = if result == :unavailable
                '認証サービスに接続できません。少し時間をおいて、登録画面を開き直してお試しください。'
              else
                '認証を確認できませんでした。もう一度認証を行い、パスワードを入力して登録してください。'
              end
    Rails.logger.error(result == :unavailable ? '[Turnstile] registration unavailable' : '[Turnstile] registration rejected')
    status = result == :unavailable ? :service_unavailable : :unprocessable_entity
    unless request.format.html?
      render plain: message, status: status
      return
    end

    # Build an unsaved Devise resource so users can retry without losing email/name.
    # Passwords are deliberately cleared and no registration side effects run.
    build_resource(sign_up_params)
    clean_up_passwords(resource)
    set_minimum_password_length
    resource.errors.add(:base, message)
    render :new, status: status
  end
end
