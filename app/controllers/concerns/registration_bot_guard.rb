# frozen_string_literal: true

module RegistrationBotGuard
  extend ActiveSupport::Concern

  included do
    prepend_before_action :reject_automated_registration, only: :create
  end

  private

  def reject_automated_registration
    return if params[:registration_website].blank?

    Rails.logger.error('[AbuseProtection] registration honeypot rejected')
    response.headers['Cache-Control'] = 'no-store'
    render plain: '登録を完了できませんでした。登録画面からもう一度お試しください。', status: :unprocessable_entity
  end
end
