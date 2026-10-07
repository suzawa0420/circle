require 'test_helper'
require_relative '../support/chat_records'

class ChatModerationTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords
  setup do
    create_chat_records
    @master = Webmaster.create!(id: 1, email: 'moderator@example.test', password: 'test-password-123')
    @spam = '性愛預約服務 https://t.me/spam-test LINE ID: bad'
  end

  test 'held inquiry has no recipient visibility notifications or unread count' do
    login_member
    @conversation.chat_messages.destroy_all
    @conversation.update!(owner_notification_due_at: nil)
    post message_conversation_path(@conversation), params: { message: { body: @spam } }
    assert_response :redirect
    held = @conversation.chat_messages.order(:id).last
    assert_equal 'held', held.moderation_status
    assert_nil @conversation.reload.owner_notification_due_at
    get conversation_path(@conversation)
    assert_includes response.body, '相手にはまだ配信されていません'
    get messages_conversation_path(@conversation), as: :json
    assert_equal '運営確認中', response.parsed_body['receipts'][held.id.to_s]
    delete destroy_member_session_path
    login_owner
    get conversations_path
    assert_not_includes response.body, @member.nickname
    assert_select '.mobile-bottom-nav__badge', count: 0
    get conversation_path(@conversation)
    assert_not_includes response.body, '性愛'
    get messages_conversation_path(@conversation), as: :json
    assert_not_includes response.parsed_body['html'], '性愛'
    assert_equal 0, @conversation.chat_messages.unread_by('owner', @conversation.reload.owner_read_message_id).count
    post message_conversation_path(@conversation), params: { message: { body: '返信です' } }
    assert_nil @conversation.reload.accepted_at
    @conversation.update!(owner_notification_due_at: 1.minute.ago)
    assert_no_difference 'ActionMailer::Base.deliveries.size' do
      ChatMaintenance.deliver_pending(@conversation, 'owner')
    end
  end

  test 'release of older held message remains unread after newer delivered messages were read' do
    held = @conversation.send_message!('member', @spam)
    later = @conversation.send_message!('member', '参加希望日は土曜日です。')
    @conversation.mark_read!('owner', through: later.id)
    assert_not @conversation.message_read?(held)
    login_member
    get messages_conversation_path(@conversation), as: :json
    version = response.parsed_body['history_version']
    assert held.moderate!('approve')
    assert_not held.moderate!('approve')
    assert_not @conversation.message_read?(held.reload)
    assert_equal 1, @conversation.chat_messages.unread_by('owner', later.id).count
    assert @conversation.reload.owner_notification_due_at
    get messages_conversation_path(@conversation), as: :json
    assert_not_equal version, response.parsed_body['history_version']
    assert_equal '未読', response.parsed_body['receipts'][held.id.to_s]
    assert_equal held.id, response.parsed_body['latest_id']
    delete destroy_member_session_path
    login_owner
    get conversation_path(@conversation)
    assert_includes response.body, '性愛'
    assert @conversation.reload.message_read?(held.reload)
    assert_nil @conversation.owner_notification_due_at
  end

  test 'only master may moderate and master viewing never changes read status' do
    held = @conversation.send_message!('member', @spam)
    get super_admin_chat_moderations_path
    assert_redirected_to new_webmaster_session_path
    login_member
    patch super_admin_chat_moderation_path(held), params: { decision: 'approve' }
    assert_equal 'held', held.reload.moderation_status
    post webmaster_session_path, params: { webmaster: { email: @master.email, password: 'test-password-123' } }
    before = @conversation.reload.owner_read_message_id
    get super_admin_chat_moderations_path
    assert_response :success
    assert_includes response.body, '成人向け'
    assert_select '.wm-badge', text: '8点'
    get super_admin_conversation_path(@conversation)
    assert_equal before, @conversation.reload.owner_read_message_id
    patch super_admin_chat_moderation_path(held), params: { decision: 'spam' }
    assert_redirected_to super_admin_chat_moderations_path
    assert_equal 'spam', held.reload.moderation_status
    assert ChatSpamDestination.exists?(destination: 't.me/spam-test')
    assert @conversation.send_message!('member', 'https://t.me/spam-test').moderation_status == 'held'
    assert @conversation.send_message!('member', 'https://t.me/friendly').delivered?
    patch super_admin_chat_moderation_path(held), params: { decision: 'approve' }
    assert_equal 'spam', held.reload.moderation_status
  end

  private
  def login_member
    post member_session_path, params: { member: { email: @member.email, password: 'test-password-123' } }
  end
  def login_owner
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
  end
end
