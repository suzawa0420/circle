# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class AccountEmailRecoveryTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include Devise::Test::IntegrationHelpers

  test 'each reset form identifies the account type and links to the other form' do
    get new_admin_user_password_path
    assert_response :success
    assert_select 'h1', text: 'サークル主催者のパスワード再設定'
    assert_includes response.body, 'サークルの連絡先とは異なる場合があります'
    assert_select 'a[href=?]', new_member_password_path

    get new_member_password_path
    assert_response :success
    assert_select 'a[href=?]', new_admin_user_password_path
  end

  { admin_user: AdminUser, member: Member }.each do |role, model|
    test "#{role} password reset sends a usable link for the matching role" do
      account = create_account(model)
      assert_difference('ActionMailer::Base.deliveries.size', 1) do
        post public_send("#{role}_password_path"), params: { role => { email: account.email.upcase } }
      end
      mail = ActionMailer::Base.deliveries.last
      assert_equal [account.email], mail.to
      link = Nokogiri::HTML(mail.body.decoded).at_css('a[href]')['href']
      uri = URI.parse(link)
      assert_equal public_send("edit_#{role}_password_path"), uri.path
      assert account.reload.reset_password_sent_at.present?
      get uri.request_uri
      assert_response :success
      assert_select 'input[name=?]', "#{role}[reset_password_token]"
    end

    test "#{role} provider failures keep the same public password reset response" do
      account = create_account(model)
      fail_mail do
        assert_no_difference('ActionMailer::Base.deliveries.size') do
          post public_send("#{role}_password_path"), params: { role => { email: account.email } }
        end
      end
      assert_response :see_other
      assert_redirected_to public_send("new_#{role}_password_path")
      follow_redirect!
      assert_includes response.body, AccountPasswordRecovery::RESET_NOTICE
    end

    test "#{role} verification can be resent immediately after a transport error" do
      account = create_account(model)
      sign_in account
      fail_mail do
        post public_send("#{role}_email_verification_path")
      end
      assert_response :see_other
      assert_nil account.reload.verification_sent_at
      follow_redirect!
      assert_includes response.body, '確認メールを送信できませんでした'
      assert_difference('ActionMailer::Base.deliveries.size', 1) do
        post public_send("#{role}_email_verification_path")
      end
      assert account.reload.verification_sent_at.present?
    end
  end

  { admin_user: [AdminUser, Member], member: [Member, AdminUser] }.each do |role, (matching_model, other_model)|
    test "#{role} valid submissions do not disclose whether an account exists" do
      registered = create_account(matching_model)
      other_role = create_account(other_model)
      path = public_send("#{role}_password_path")
      redirect_path = public_send("new_#{role}_password_path")

      [registered.email, other_role.email, 'unknown@example.test'].each_with_index do |email, i|
        assert_difference('ActionMailer::Base.deliveries.size', i.zero? ? 1 : 0) do
          post path, params: { role => { email: email } }
        end
        assert_response :see_other
        assert_redirected_to redirect_path
        follow_redirect!
        assert_includes response.body, AccountPasswordRecovery::RESET_NOTICE
      end
      assert_nil other_role.reload.reset_password_sent_at
    end

    test "#{role} malformed address shows an explicit input error without sending mail" do
      assert_no_difference('ActionMailer::Base.deliveries.size') do
        post public_send("#{role}_password_path"), params: { role => { email: 'not-an-email' } }
      end
      assert_equal 422, response.status
      assert_includes response.body, 'メールアドレスの形式を確認してください'
    end
  end

  private

  def create_account(model)
    model.create!(email: "mail-#{model.name.downcase}@example.test", password: 'valid-password-123',
      nickname: 'メール確認')
  end

  class FailingAccountMailTransport
    def initialize(_settings); end

    def deliver!(_message)
      raise Aws::SES::Errors::MessageRejected.new(nil, 'simulated delivery failure')
    end
  end

  def fail_mail
    ActionMailer::Base.add_delivery_method :account_email_failure_probe, FailingAccountMailTransport
    original = ActionMailer::Base.delivery_method
    ActionMailer::Base.delivery_method = :account_email_failure_probe
    yield
  ensure
    ActionMailer::Base.delivery_method = original
  end
end
