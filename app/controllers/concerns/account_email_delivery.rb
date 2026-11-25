# frozen_string_literal: true

module AccountEmailDelivery
  DELIVERY_ERRORS = [
    Aws::SES::Errors::ServiceError,
    Seahorse::Client::NetworkingError,
    Aws::Errors::MissingCredentialsError,
    IOError, SystemCallError, SocketError, Timeout::Error
  ].freeze

  private

  def log_account_email_failure(flow, role, error)
    # Provider error text can contain the recipient. Never log it or a reset token here.
    Rails.logger.warn("account_email.delivery_failed flow=#{flow} role=#{role} error=#{error.class.name} request_id=#{request.request_id}")
  end
end
