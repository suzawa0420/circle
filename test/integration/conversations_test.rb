require 'test_helper'
require_relative '../support/chat_records'

class ConversationsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords
  setup do
    create_chat_records
  end

  test 'message URLs are linked safely for participants owners and polling' do
    accept_conversation
    @conversation.send_message!('owner', "ご案内：https://example.test/join?a=1&b=2\n<script>alert(1)</script> javascript:alert(2)")
    [@member, @owner].each do |account|
      sign_in account
      get conversation_path(@conversation)
      assert_response :success
      assert_select '.chat-body a.message-url[href="https://example.test/join?a=1&b=2"]', count: 1 do |links|
        assert_equal '_blank', links.first['target']
        assert_includes links.first['rel'], 'noopener'
      end
      assert_select '.chat-body script', count: 0
      assert_select '.chat-body a[href^="javascript:"]', count: 0
      get messages_conversation_path(@conversation), as: :json
      assert_response :success
      assert_includes response.parsed_body.to_s, 'message-url'
      sign_out account
    end
  end

  test 'inbox shows latest preview and unread state for each role without leaking other threads' do
    accept_conversation
    other = Conversation.for_member!(@circle, @other_member)
    other.send_message!('member', '別の参加者の非公開メッセージ')
    sign_in @member
    get conversations_path
    assert_response :success
    assert_select '.chat-talk', count: 1
    assert_select '.chat-talk__preview', text: 'お問い合わせありがとうございます。ぜひお越しください。'
    assert_select '.chat-badge', text: '未読'
    assert_not_includes response.body, '別の参加者の非公開メッセージ'
    get conversation_path(@conversation)
    assert_select 'body.chat-thread-page'
    assert_select '.chat-message:not(.chat-message--mine) .chat-avatar', count: 1
    assert_select '.chat-composer textarea[name="message[body]"]', count: 1
    get conversations_path
    assert_select '.chat-badge', count: 0
    sign_out @member
    sign_in @owner
    # Reading an old thread must not move it above a more recent message.
    @conversation.touch(time: 1.minute.from_now)
    get conversations_path
    assert_select '.chat-talk', count: 2
    assert_select '.chat-talk:first-child .chat-talk__name', text: "#{@other_member.nickname}さん"
    assert_select '.chat-talk:first-child .chat-talk__preview', text: '別の参加者の非公開メッセージ'
  end

  test 'anonymous old contact entry leads to registration and old anonymous review creation is disabled' do
    get new_user_user_contact_path(@circle)
    assert_redirected_to new_user_conversation_path(@circle)
    follow_redirect!
    assert_redirected_to new_member_registration_path
    post user_reviews_path(@circle), params: { review: { review: 1, comment: '未登録で投稿します。' } }
    assert_response :forbidden
    assert_empty @circle.reviews
    post user_user_contacts_path(@circle), params: { user_contact: { message: '旧フォームからの送信' } }
    assert_redirected_to new_user_conversation_path(@circle)
    assert_empty @circle.user_contacts
  end

  test 'only participant and actual circle owner can read and mutate conversation, not arbitrary ids' do
    sign_in @other_member
    [[:get, messages_conversation_path(@conversation)], [:get, conversation_path(@conversation)], [:post, message_conversation_path(@conversation)],
     [:post, block_conversation_path(@conversation)], [:delete, block_conversation_path(@conversation)],
     [:put, review_conversation_path(@conversation)], [:delete, review_conversation_path(@conversation)],
     [:post, report_conversation_path(@conversation)], [:post, no_reply_conversation_path(@conversation)]].each do |method, path|
      assert_raises(ActiveRecord::RecordNotFound) { public_send(method, path) }
    end
    get conversations_path
    assert_response :success
    assert_not_includes response.body, @circle.name
    sign_out @other_member
    sign_in @member
    get conversation_path(@conversation)
    assert_response :success
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_select 'textarea[name="message[body]"]'
    sign_out @member
    sign_in @owner
    get conversation_path(@conversation)
    assert_response :success
    assert_select "a[href='#{member_profile_path(@member)}']"
  end

  test 'another circle owner cannot access messages or reports' do
    outsider = AdminUser.create!(email: 'outsider@example.test', password: 'test-password-123')
    User.create!(@circle.attributes.except('id', 'created_at', 'updated_at', 'unique_id').merge('admin_user_id' => outsider.id, 'name' => '別のサークル'))
    sign_in outsider
    assert_raises(ActiveRecord::RecordNotFound) { get conversation_path(@conversation) }
    get super_admin_chat_reports_path
    assert_redirected_to new_webmaster_session_path
  end

  test 'first reply enables blind reviews, public profiles contain no private conversation or email' do
    sign_in @member
    post message_conversation_path(@conversation), params: { message: { body: '非公開メッセージ秘密文言', sender_role: 'owner' } }
    assert_nil @conversation.reload.accepted_at
    sign_out @member
    sign_in @owner
    post message_conversation_path(@conversation), params: { message: { body: '初回の返信です。', sender_role: 'member' } }
    assert_redirected_to conversation_path(@conversation)
    assert @conversation.reload.accepted_at
    put review_conversation_path(@conversation), params: { evaluation: owner_evaluation }
    assert_response :redirect
    sign_out @owner
    sign_in @member
    get conversation_path(@conversation)
    assert_not_includes response.body, owner_evaluation[:comment]
    get member_profile_path(@member)
    assert_response :success
    assert_not_includes response.body, owner_evaluation[:comment]
    put review_conversation_path(@conversation), params: { evaluation: member_evaluation }
    assert_response :redirect
    sign_out @member
    get member_profile_path(@member)
    assert_response :success
    assert_includes response.body, owner_evaluation[:comment]
    assert_not_includes response.body, '非公開メッセージ秘密文言'
    assert_not_includes response.body, @member.email
    get user_reviews_path(@circle)
    assert_response :success
    assert_includes response.body, member_evaluation[:comment]
    assert_select "a[href='#{member_profile_path(@member)}']"
    get circle_path(@circle)
    assert_response :success
    assert_includes response.body, member_evaluation[:comment]
  end

  test 'unverified member cannot send and verification requires the same logged in member' do
    @member.update!(email_verified_at: nil)
    sign_in @member
    get new_user_conversation_path(@circle)
    assert_redirected_to member_email_verification_path
    post message_conversation_path(@conversation), params: { message: { body: '未認証で送信します。' } }
    assert_redirected_to member_email_verification_path
    assert_equal 1, @conversation.chat_messages.where.not(sender_role: 'system').count
    token = @member.signed_id(purpose: @member.email_verification_purpose, expires_in: 24.hours)
    get confirm_member_email_verification_path(token: token)
    assert_response :success
    assert_nil @member.reload.email_verified_at
    patch member_email_verification_path, params: { token: token }
    assert @member.reload.email_verified?
    assert_redirected_to member_path(@member)
    sign_out @member
    sign_in @other_member
    @other_member.update!(email_verified_at: nil)
    patch member_email_verification_path, params: { token: token }
    assert_nil @other_member.reload.email_verified_at
  end

  test 'expired email links and links issued before email change cannot verify' do
    sign_in @member
    token = @member.signed_id(purpose: @member.email_verification_purpose, expires_in: 24.hours)
    @member.update!(email: 'new-address@example.test')
    patch member_email_verification_path, params: { token: token }
    assert_nil @member.reload.email_verified_at
    token = @member.signed_id(purpose: @member.email_verification_purpose, expires_in: 24.hours)
    travel 25.hours do
      patch member_email_verification_path, params: { token: token }
      assert_nil @member.reload.email_verified_at
    end
  end

  test 'email verification sends a local test mail and throttles resend' do
    sign_in @member
    assert_difference('ActionMailer::Base.deliveries.size', 1) { post member_email_verification_path }
    assert_no_difference('ActionMailer::Base.deliveries.size') { post member_email_verification_path }
  end

  test 'member cannot undo owner block, neither can send, both retain evaluation rights' do
    accept_conversation
    sign_in @owner
    post block_conversation_path(@conversation)
    sign_out @owner
    sign_in @member
    delete block_conversation_path(@conversation)
    assert @conversation.reload.owner_blocked?
    assert_no_difference('ChatMessage.count') do
      post message_conversation_path(@conversation), params: { message: { body: 'ブロック中に送信します。' } }
    end
    put review_conversation_path(@conversation), params: { evaluation: member_evaluation }
    assert_equal 1, @conversation.conversation_reviews.count
  end

  test 'legacy review cannot be edited, can be deleted by author and deletion consumes entitlement' do
    review = Review.create!(user: @circle, member: @member, review: 1, comment: '以前に投稿した口コミです。')
    sign_in @other_member
    delete user_review_path(@circle, review)
    assert_response :forbidden
    sign_out @other_member
    sign_in @member
    patch user_review_path(@circle, review), params: { review: { comment: '編集した内容です。' } }
    assert_response :forbidden
    delete user_review_path(@circle, review)
    assert_not Review.exists?(review.id)
    assert @conversation.reload.legacy_member_review?
    accept_conversation
    put review_conversation_path(@conversation), params: { evaluation: member_evaluation }
    assert_empty @circle.reviews
  end

  test 'published review deletion through old endpoint also prevents re-posting and preserves counterpart' do
    accept_conversation
    @conversation.submit_review!('member', member_evaluation)
    @conversation.submit_review!('owner', owner_evaluation)
    sign_in @member
    delete user_review_path(@circle, @circle.reviews.first)
    assert_empty @circle.reviews
    assert_equal 1, @member.received_conversation_reviews.count
    put review_conversation_path(@conversation), params: { evaluation: member_evaluation }
    assert_empty @circle.reviews
  end

  test 'reports are private, message targets are scoped, no reply flag clears on owner reply' do
    sign_in @member
    post no_reply_conversation_path(@conversation)
    assert_equal 'NG', @conversation.reload.respond_check
    post report_conversation_path(@conversation), params: { report: { reason: '高評価の投稿を強要されました。' }, message_id: @conversation.chat_messages.first.id }
    assert_equal 1, ChatReport.count
    other = Conversation.for_member!(@circle, @other_member)
    message = other.send_message!('member', '別の会話のメッセージです。')
    assert_raises(ActiveRecord::RecordNotFound) do
      post report_conversation_path(@conversation), params: { report: { reason: '他の会話を通報します。' }, message_id: message.id }
    end
    sign_out @member
    sign_in @owner
    get conversation_path(@conversation)
    assert_not_includes response.body, '高評価の投稿を強要されました。'
    post message_conversation_path(@conversation), params: { message: { body: '返信が遅くなりました。' } }
    assert_nil @conversation.reload.respond_check
  end

  test 'chat escapes scripts and rejects oversized or blank messages without creating empty conversations' do
    sign_in @member
    post message_conversation_path(@conversation), params: { message: { body: '<script>alert("xss")</script>' } }
    get conversation_path(@conversation)
    assert_response :success
    assert_select '.chat-history script', count: 0
    assert_no_difference('ChatMessage.count') do
      post message_conversation_path(@conversation), params: { message: { body: 'a' * 2001 } }
    end
    sign_out @member
    sign_in @other_member
    assert_no_difference('Conversation.count') do
      post user_conversations_path(@circle), params: { message: { body: '' } }
    end
  end

  test 'new contact form contains no external LINE entry and creates one conversation for a pair' do
    @circle.update!(line_id: 'https://line.me/example', contact: 'line')
    sign_in @other_member
    get new_user_conversation_path(@circle)
    assert_response :success
    assert_select 'a[href="https://line.me/example"]', count: 0
    assert_difference('Conversation.count', 1) do
      post user_conversations_path(@circle), params: { message: { body: '参加に関する問い合わせです。', member_id: @member.id } }
    end
    conversation = Conversation.find_by!(user: @circle, member: @other_member)
    assert_redirected_to conversation_path(conversation)
    assert_no_difference('Conversation.count') do
      post user_conversations_path(@circle), params: { message: { body: '続けての問い合わせです。' } }
    end
  end

  test 'owner mail link returns to the conversation after organizer login' do
    get conversation_path(@conversation)
    assert_redirected_to login_path
    sign_in @owner
    assert_redirected_to conversation_path(@conversation)
  end

  test 'polling is private marks read and contains only this conversations escaped messages' do
    accept_conversation
    sign_in @member
    get messages_conversation_path(@conversation), as: :json
    assert_response :success
    assert_includes response.headers['Cache-Control'], 'no-store'
    payload = response.parsed_body
    assert payload['accepted']
    assert_includes payload['html'], 'ぜひお越しください'
    assert_nil @conversation.reload.member_notification_due_at
    assert_select 'script', count: 0
  end

  test 'owner cannot set computed review score through circle editing' do
    @circle.update!(review_score: '2.5')
    sign_in @owner
    patch user_path(@circle), params: { user: { review_score: '5', review_permit: false } }
    assert_response :redirect
    assert_equal '2.5', @circle.reload.review_score
    assert @circle.review_permit
  end

  test 'a participant account with the organizers verified email cannot contact itself' do
    @other_member.update!(email: @owner.email)
    @other_member.update!(email_verified_at: Time.current)
    sign_in @other_member
    assert_no_difference('Conversation.count') do
      post user_conversations_path(@circle), params: { message: { body: '自作自演の問い合わせです。' } }
    end
  end

  test 'registration starts unverified and confirmation leads to participant mypage' do
    get new_user_conversation_path(@circle)
    assert_redirected_to new_member_registration_path
    get new_member_registration_path
    assert_response :success
    token = Nokogiri::HTML(response.body).at_css('input[name="spam_form_token"]')['value']
    assert_difference('Member.count', 1) do
      post member_registration_path, params: {
        member: { email: 'new-chat-account@example.test', nickname: '新規参加者', password: 'test-password-123', password_confirmation: 'test-password-123' },
        spam_form_token: token, contact_website: '', registration_website: ''
      }
    end
    assert_redirected_to member_email_verification_path
    get member_email_verification_path
    assert_select 'script[src*="googlesyndication"]', count: 0
    assert_not_includes response.body, 'GTM-MD88D9HB'
    member = Member.find_by!(email: 'new-chat-account@example.test')
    assert_not member.email_verified?
    patch member_email_verification_path, params: { token: member.signed_id(purpose: member.email_verification_purpose, expires_in: 24.hours) }
    assert_redirected_to member_path(member)
  end

  test 'empty inbox gives role appropriate guidance' do
    @conversation.destroy!
    sign_in @member
    get conversations_path
    assert_select '.chat-card', text: /気になるサークルに問い合わせると/
    assert_select ".chat-card a[href='#{circles_path}']", text: 'サークルを探す'
    sign_out @member
    sign_in @owner
    get conversations_path
    assert_select '.chat-card', text: /参加希望者からのお問い合わせが届くと/
    assert_select ".chat-card a[href='/users/#{@circle.id}/mypage']", text: 'マイページへ戻る'
    assert_not_includes response.body, '気になるサークルに問い合わせると'
  end


  test 'master administrator can review reported evidence while normal owner cannot' do
    master = Webmaster.create!(id: 1, email: 'webmaster@example.test', password: 'test-password-123')
    report = @conversation.chat_reports.create!(reporter_role: 'member', reason: '口コミの削除を強要されました。', chat_message: @conversation.chat_messages.first)
    post webmaster_session_path, params: { webmaster: { email: master.email, password: 'test-password-123' } }
    get super_admin_chat_reports_path
    assert_response :success
    get super_admin_chat_report_path(report)
    assert_response :success
    assert_includes response.body, '口コミの削除を強要されました。'
    assert_includes response.body, 'はじめまして。参加できますか？'
    patch super_admin_chat_report_path(report)
    assert report.reload.resolved_at
  end

  private

  def sign_in(account)
    if account.is_a?(Member)
      post member_session_path, params: { member: { email: account.email, password: 'test-password-123' } }
    else
      post admin_user_session_path, params: { admin_user: { email: account.email, password: 'test-password-123' } }
    end
    assert_response :redirect
  end

  def sign_out(account)
    delete(account.is_a?(Member) ? destroy_member_session_path : destroy_admin_user_session_path)
    assert_response :redirect
  end

end
