require 'test_helper'
require_relative '../support/chat_records'

class AdminUserEmailVerificationsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords
  setup do
    create_chat_records
    @owner.update!(email_verified_at: nil)
  end

  test 'unverified owner can read but cannot send, accept or evaluate; new circle registration is gated' do
    login(@owner)
    get conversation_path(@conversation)
    assert_response :success
    assert_select "a[href='#{admin_user_email_verification_path}']"
    assert_no_difference('ChatMessage.count') do
      post message_conversation_path(@conversation), params: { message: { body: '認証前に返信します。' } }
    end
    assert_redirected_to admin_user_email_verification_path
    assert_nil @conversation.reload.accepted_at
    put review_conversation_path(@conversation), params: { evaluation: owner_evaluation }
    assert_redirected_to admin_user_email_verification_path
    assert_empty @conversation.conversation_reviews
    get new_user_path
    assert_redirected_to admin_user_email_verification_path
    assert_no_difference('User.count') { post users_path, params: { user: { name: '未認証サークル' } } }
    assert_redirected_to admin_user_email_verification_path
  end

  test 'verification sends local mail, limits resend and confirms only after button with correct account' do
    login(@owner)
    get admin_user_email_verification_path
    assert_response :success
    assert_not_includes response.body, 'GTM-MD88D9HB'
    assert_select 'script[src*="googlesyndication"]', count: 0
    assert_equal 'same-origin', response.headers['Referrer-Policy']
    assert_difference('ActionMailer::Base.deliveries.size', 1) { post admin_user_email_verification_path }
    mail = ActionMailer::Base.deliveries.last
    assert_equal [@owner.email], mail.to
    assert_includes mail.body.decoded, '/admin_user_email_verification/confirm?token='
    assert_no_difference('ActionMailer::Base.deliveries.size') { post admin_user_email_verification_path }
    token = owner_token
    get confirm_admin_user_email_verification_path(token: token)
    assert_response :success
    assert_nil @owner.reload.email_verified_at
    patch admin_user_email_verification_path, params: { token: token }
    assert @owner.reload.email_verified?
    post message_conversation_path(@conversation), params: { message: { body: '認証後に初回返信しました。' } }
    assert_redirected_to conversation_path(@conversation)
    assert @conversation.reload.accepted_at
  end

  test 'another owner and participant tokens cannot verify this account' do
    other = AdminUser.create!(email: 'other-verify-owner@example.test', password: 'test-password-123')
    wrong_token = other.signed_id(purpose: other.email_verification_purpose, expires_in: 24.hours)
    login(@owner)
    patch admin_user_email_verification_path, params: { token: wrong_token }
    assert_nil @owner.reload.email_verified_at
    participant_token = @member.signed_id(purpose: @member.email_verification_purpose, expires_in: 24.hours)
    patch admin_user_email_verification_path, params: { token: participant_token }
    assert_nil @owner.reload.email_verified_at
    patch admin_user_email_verification_path, params: { token: 'not-a-signed-token' }
    assert_nil @owner.reload.email_verified_at
  end

  test 'links expire and are invalidated by email change; verified status resets on change' do
    token = owner_token
    login(@owner)
    travel 25.hours do
      patch admin_user_email_verification_path, params: { token: token }
      assert_nil @owner.reload.email_verified_at
    end
    token = owner_token
    @owner.update!(email_verified_at: Time.current, verification_sent_at: Time.current)
    @owner.update!(email: 'changed-owner@example.test')
    assert_nil @owner.email_verified_at
    assert_nil @owner.verification_sent_at
    patch admin_user_email_verification_path, params: { token: token }
    assert_nil @owner.reload.email_verified_at
  end

  test 'new owner with no circle can verify and is returned to circle registration without redirect loop' do
    newcomer = AdminUser.create!(email: 'newcomer-owner@example.test', password: 'test-password-123')
    login(newcomer)
    get admin_user_email_verification_path
    assert_response :success
    post admin_user_email_verification_path
    assert_response :redirect
    token = newcomer.signed_id(purpose: newcomer.email_verification_purpose, expires_in: 24.hours)
    patch admin_user_email_verification_path, params: { token: token }
    assert_redirected_to new_user_path
    follow_redirect!
    assert_response :success
    get edit_admin_user_registration_path
    assert_response :success
  end

  test 'signup uses owner verification and changing email returns to verification' do
    get new_admin_user_registration_path
    token = Nokogiri::HTML(response.body).at_css('input[name="spam_form_token"]')['value']
    assert_difference('AdminUser.count', 1) do
      post admin_user_registration_path, params: {
        admin_user: { email: 'registered-owner@example.test', password: 'test-password-123', password_confirmation: 'test-password-123' },
        spam_form_token: token, contact_website: '', registration_website: ''
      }
    end
    assert_redirected_to admin_user_email_verification_path
    follow_redirect!
    assert_response :success
    owner = AdminUser.find_by!(email: 'registered-owner@example.test')
    owner.update!(email_verified_at: Time.current)
    patch admin_user_registration_path, params: { admin_user: { email: 'updated-owner@example.test', current_password: 'test-password-123' } }
    assert_redirected_to admin_user_email_verification_path
    assert_nil owner.reload.email_verified_at
  end

  test 'anonymous visitors cannot verify, resend or see email address' do
    get admin_user_email_verification_path
    assert_redirected_to new_admin_user_session_path
    post admin_user_email_verification_path
    assert_redirected_to new_admin_user_session_path
    patch admin_user_email_verification_path, params: { token: owner_token }
    assert_redirected_to new_admin_user_session_path
  end

  test 'model also rejects unverified owner messages without controller' do
    assert_raises(Conversation::NotAllowed) { @conversation.send_message!('owner', '直接の送信です。') }
    assert_nil @conversation.reload.accepted_at
  end

  private
  def owner_token
    @owner.signed_id(purpose: @owner.email_verification_purpose, expires_in: 24.hours)
  end

  def login(account)
    post admin_user_session_path, params: { admin_user: { email: account.email, password: 'test-password-123' } }
    assert_response :redirect
  end
end
