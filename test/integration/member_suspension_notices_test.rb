require 'test_helper'
require_relative '../support/chat_records'

class MemberSuspensionNoticesTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    @master = Webmaster.create!(id: 1, email: 'suspension-view@example.test', password: 'test-password-123')
  end

  test 'historical suspension appears for webmaster owner and participant without writing or scheduling mail' do
    # Simulate a suspension made before the message callback existed.
    @member.update_columns(suspended_at: 1.hour.ago, suspension_reason: '非公開の停止理由')
    original_state = @conversation.reload.attributes.slice('owner_read_message_id', 'member_read_message_id', 'owner_notification_due_at', 'member_notification_due_at')
    login_master
    assert_no_difference ['ChatMessage.count', 'ActionMailer::Base.deliveries.size'] do
      get super_admin_conversation_path(@conversation, page: 1)
    end
    assert_response :success
    assert_notice
    assert_equal original_state, @conversation.reload.attributes.slice(*original_state.keys)
    delete destroy_webmaster_session_path
    login_owner
    assert_no_difference ['ChatMessage.count', 'ActionMailer::Base.deliveries.size'] do
      get conversation_path(@conversation)
      assert_notice
      get messages_conversation_path(@conversation), as: :json
      assert_includes response.parsed_body['html'], ChatMessage::MEMBER_SUSPENSION_NOTICE
    end
    assert_nil @conversation.reload.owner_notification_due_at
    assert_nil @conversation.member_notification_due_at
    delete destroy_admin_user_session_path
    post member_session_path, params: { member: { email: @member.email, password: 'test-password-123' } }
    get conversation_path(@conversation)
    assert_notice
  end

  test 'stored current suspension message is not duplicated by the fallback' do
    @member.update!(suspended_at: Time.current)
    login_master
    get super_admin_conversation_path(@conversation, page: 1)
    assert_notice
    assert_select '[data-member-suspension-notice]', count: 0
    delete destroy_webmaster_session_path
    login_owner
    get conversation_path(@conversation)
    assert_notice
    assert_select '[data-member-suspension-notice]', count: 0
  end

  test 'suspension is visible on older pages even if stored notice is on another page' do
    51.times { @conversation.chat_messages.create!(sender_role: 'member', body: '以前のやり取りです。') }
    @member.update!(suspended_at: Time.current)
    login_master
    get super_admin_conversation_path(@conversation, page: 1)
    assert_notice
    assert_select '[data-member-suspension-notice]', count: 1
    last_page = (@conversation.chat_messages.count.to_f / ConversationJump::PAGE_SIZE).ceil
    get super_admin_conversation_path(@conversation, page: last_page)
    assert_notice
    assert_select '[data-member-suspension-notice]', count: 0
    delete destroy_webmaster_session_path
    login_owner
    get conversation_path(@conversation, page: 2)
    assert_notice
    assert_select '[data-member-suspension-notice]', count: 1
  end

  test 'report history shows a historical suspension and fallback disappears after resume' do
    @member.update_columns(suspended_at: 1.hour.ago)
    report = ChatReport.create!(conversation: @conversation, reporter_role: 'owner', reason: '営業目的の問い合わせです。')
    login_master
    get super_admin_chat_report_path(report)
    assert_notice
    @member.update!(suspended_at: nil)
    get super_admin_conversation_path(@conversation, page: 1)
    assert_not_includes response.body, ChatMessage::MEMBER_SUSPENSION_NOTICE
    assert_select '[data-member-suspension-notice]', count: 0
  end

  private

  def assert_notice
    assert response.body.include?(ChatMessage::MEMBER_SUSPENSION_NOTICE), '利用停止案内が表示されていません'
    assert_select '.cb-platform-notice .message-role--system', text: '運営からのお知らせ', count: 1
    assert_not_includes response.body, '非公開の停止理由'
  end

  def login_master
    post webmaster_session_path, params: { webmaster: { email: @master.email, password: 'test-password-123' } }
  end

  def login_owner
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
  end
end
