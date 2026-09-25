module SpamProtection
  extend ActiveSupport::Concern

  included do
    helper_method :spam_form_token
  end

  private

  def spam_form_token(scope)
    response.headers['Cache-Control'] = 'private, no-store'
    session[:spam_form_id] ||= SecureRandom.hex(32)
    Rails.application.message_verifier(:spam_form).generate(
      session[:spam_form_id], purpose: scope, expires_in: 12.hours
    )
  end

  def verify_spam_form!(scope)
    token = params[:spam_form_token]
    valid = token.is_a?(String) && token.bytesize <= 2048 &&
      params[:contact_website].blank? && session[:spam_form_id].present? &&
      Rails.application.message_verifier(:spam_form).verified(token, purpose: scope) == session[:spam_form_id]
    return true if valid

    response.headers['Cache-Control'] = 'no-store'
    render plain: '送信を確認できませんでした。ページを再読み込みして、もう一度お試しください。',
           status: :unprocessable_entity
    false
  end

  def verify_registration_form
    verify_spam_form!("registration:#{resource_name}")
  end
end
