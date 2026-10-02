require 'test_helper'
require 'minitest/mock'

class RegistrationEmailVerificationTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  { member: [Member, :verify_email], admin_user: [AdminUser, :verify_owner_email] }.each do |role, (model, mailer_action)|
    test "#{role} signup automatically sends exactly one confirmation mail and allows later resend" do
      parameters = signup_parameters(role)
      assert_difference("#{model}.count", 1) do
        assert_difference('ActionMailer::Base.deliveries.size', 1) do
          post public_send("#{role}_registration_path"), params: parameters
        end
      end
      assert_redirected_to public_send("#{role}_email_verification_path")
      account = model.find_by!(email: parameters[role][:email])
      assert_not account.email_verified?
      assert account.verification_sent_at.present?
      assert_equal [account.email], ActionMailer::Base.deliveries.last.to
      assert_includes ActionMailer::Base.deliveries.last.body.decoded, "/#{role}_email_verification/confirm?token="
      assert_no_difference('ActionMailer::Base.deliveries.size') do
        follow_redirect!
        assert_response :success
        assert_select 'input[type="submit"][value="確認メールを再送"]'
        get public_send("#{role}_email_verification_path")
        post public_send("#{role}_email_verification_path")
      end
      travel 2.minutes do
        assert_difference('ActionMailer::Base.deliveries.size', 1) do
          post public_send("#{role}_email_verification_path")
        end
      end
    end

    test "#{role} invalid signup does not send confirmation mail" do
      parameters = signup_parameters(role)
      parameters[role][:email] = 'invalid-email'
      assert_no_difference("#{model}.count") do
        assert_no_difference('ActionMailer::Base.deliveries.size') do
          post public_send("#{role}_registration_path"), params: parameters
        end
      end
      assert_response :success
      assert_select 'input[type="email"]'
    end

    test "#{role} mail failure preserves registration and offers a retry" do
      parameters = signup_parameters(role)
      failed_delivery = Object.new
      def failed_delivery.deliver_now
        raise IOError, 'Simulated test delivery failure'
      end
      ChatMailer.stub(mailer_action, failed_delivery) do
        assert_difference("#{model}.count", 1) do
          post public_send("#{role}_registration_path"), params: parameters
        end
      end
      assert_redirected_to public_send("#{role}_email_verification_path")
      account = model.find_by!(email: parameters[role][:email])
      assert_nil account.verification_sent_at
      assert_not account.email_verified?
      follow_redirect!
      assert_response :success
      assert_includes response.body, '確認メールを送信できませんでした'
      assert_select 'input[type="submit"][value="確認メールを送信"]'
      assert_difference('ActionMailer::Base.deliveries.size', 1) do
        post public_send("#{role}_email_verification_path")
      end
    end
  end

  private

  def signup_parameters(role)
    get public_send("new_#{role}_registration_path")
    assert_response :success
    token = Nokogiri::HTML(response.body).at_css('input[name="spam_form_token"]')['value']
    account = { email: "automatic-#{role}@example.test", password: 'test-password-123', password_confirmation: 'test-password-123' }
    account[:nickname] = '新規参加者' if role == :member
    { role => account, spam_form_token: token, contact_website: '', registration_website: '' }
  end
end
