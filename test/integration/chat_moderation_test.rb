require 'test_helper'
require_relative '../support/chat_records'

class ChatModerationTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords
  include Devise::Test::IntegrationHelpers
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
    assert_response :redirect
    follow_redirect!
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

  test 'viewing an older page marks its released message read without clearing newer unread messages' do
    held = @conversation.send_message!('member', @spam)
    held.moderate!('approve')
    held.update!(released_at: 1.hour.ago)
    ChatMessage.insert_all!(55.times.map { |i| { conversation_id: @conversation.id, sender_role: 'member', body: "新しい履歴 #{i}", created_at: Time.current, updated_at: Time.current } })
    login_owner
    get conversation_path(@conversation), params: { page: 2 }
    assert_response :success
    assert @conversation.reload.message_read?(held.reload)
    assert_equal 0, @conversation.owner_read_message_id
    assert @conversation.owner_notification_due_at
  end

  test 'participation and practice inquiries including deleted posts can be individually confirmed as spam' do
    source_owner = AdminUser.create!(email: 'moderation-practice@example.test', password: 'test-password-123', email_verified_at: Time.current)
    source = @circle.dup
    source.assign_attributes(name: '練習相手チーム', admin_user: source_owner)
    source.save!
    practice = Conversation.for_circles!(@circle, source)
    sign_in @master

    [@conversation, practice].each do |conversation|
      [false, true].each do |deleted|
        held = conversation.send_message!('member', @spam)
        held.revise!('member', delete: true) if deleted
        get super_admin_chat_moderations_path
        assert_response :success
        assert_select "form[action='#{super_admin_chat_moderation_path(held)}'] input[value=spam]", count: 1
        assert_select "form[action='#{super_admin_chat_moderation_path(held)}'] input[value=approve]", count: deleted ? 0 : 1
        if deleted
          assert_select '.wm-body', text: /メッセージを削除しました/
          patch super_admin_chat_moderation_path(held), params: { decision: 'approve' }
          assert_equal 'held', held.reload.moderation_status
          assert_nil held.reviewed_at
        end

        before = conversation.reload.attributes.slice('owner_notification_due_at', 'member_notification_due_at', 'owner_read_message_id', 'member_read_message_id')
        assert_no_difference ['ChatMessage.count', 'Conversation.count', 'ActionMailer::Base.deliveries.size'] do
          patch super_admin_chat_moderation_path(held), params: { decision: 'spam' }
        end
        assert_redirected_to super_admin_chat_moderations_path
        assert_equal 'spam', held.reload.moderation_status
        assert held.reviewed_at
        assert_equal deleted, held.deleted_at.present?
        assert_nil held.released_at
        assert_equal before, conversation.reload.attributes.slice(*before.keys)
        assert_not_includes conversation.chat_messages.deliverable.pluck(:id), held.id
        reviewed_at = held.reviewed_at
        assert_no_difference 'ChatSpamDestination.count' do
          %w[spam approve].each do |decision|
            patch super_admin_chat_moderation_path(held), params: { decision: decision }
            assert_equal 'spam', held.reload.moderation_status
            assert_equal reviewed_at, held.reviewed_at
          end
        end
        get super_admin_chat_moderations_path
        assert_select "form[action='#{super_admin_chat_moderation_path(held)}']", count: 0
        get super_admin_chat_moderations_path(status: 'spam')
        assert_response :success
      end
    end
    get super_admin_chat_moderations_path
    assert_select '.webmaster-card.wm-message', count: 0
  end

  test 'deleted held post keeps authorization and rejects invalid decisions and missing IDs' do
    held = @conversation.send_message!('member', @spam)
    held.revise!('member', delete: true)
    patch super_admin_chat_moderation_path(held), params: { decision: 'spam' }
    assert_redirected_to new_webmaster_session_path
    assert_not Webmaster.new(id: 2, email: 'not-master@example.test', password: 'test-password-123').valid?
    [@member, @owner].each do |actor|
      sign_in actor
      patch super_admin_chat_moderation_path(held), params: { decision: 'spam' }
      assert_includes [302, 403], response.status
      assert_equal 'held', held.reload.moderation_status
      sign_out actor
    end
    sign_in @master
    patch super_admin_chat_moderation_path(held), params: { decision: 'delete' }
    assert_response :unprocessable_entity
    assert_equal 'held', held.reload.moderation_status
    assert_raises(ActiveRecord::RecordNotFound) do
      patch super_admin_chat_moderation_path('invalid-id'), params: { decision: 'spam' }
    end
    assert_equal 'held', held.reload.moderation_status
  end

  test 'foreign keys prevent held reports losing their conversation or participants' do
    @conversation.send_message!('member', @spam)
    [@conversation, @member, @circle].each do |source|
      assert_raises(ActiveRecord::InvalidForeignKey) do
        source.class.transaction(requires_new: true) { source.delete }
      end
    end
    sign_in @master
    get super_admin_chat_moderations_path
    assert_response :success
  end

  private
  def login_member
    post member_session_path, params: { member: { email: @member.email, password: 'test-password-123' } }
  end
  def login_owner
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
  end
end
