require 'test_helper'
require_relative '../support/chat_records'

class ChatMessageRevisionsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    @message = @conversation.chat_messages.where(sender_role: 'member').sole
    @message.update_column(:created_at, @message.created_at.change(usec: 0))
  end

  test 'sender edits using the composer and both sides see the edited marker and polling change' do
    sign_in @member
    get conversation_path(@conversation)
    assert_select "#chat-message-#{@message.id} .chat-body .chat-message__actions", count: 1
    get messages_conversation_path(@conversation), as: :json
    version = response.parsed_body['history_version']
    created_at = @message.created_at
    patch update_message_conversation_path(@conversation, message_id: @message.id), params: { message: { body: '土曜日の参加を希望します。', sender_role: 'owner', created_at: Time.current } }
    assert_response :redirect
    assert_equal '土曜日の参加を希望します。', @message.reload.body
    assert_equal created_at, @message.created_at
    assert_equal 'member', @message.sender_role
    assert @message.edited_at
    get messages_conversation_path(@conversation), as: :json
    assert_not_equal version, response.parsed_body['history_version']
    assert_includes response.parsed_body['html'], '編集済み'
    sign_out @member
    sign_in @owner
    get conversation_path(@conversation)
    assert_select "#chat-message-#{@message.id} .chat-revision", text: '編集済み'
    assert_select "#chat-message-#{@message.id} .chat-message__actions", count: 0
  end

  test 'editing loads the reply composer with a patch form and cancellation link' do
    sign_in @member
    get conversation_path(@conversation, edit_message_id: @message.id)
    assert_response :success
    assert_select '#chat-reply-title', text: 'メッセージを編集'
    assert_select '#chat-reply form[action=?]', update_message_conversation_path(@conversation, message_id: @message.id) do
      assert_select 'input[name="_method"][value="patch"]'
      assert_select 'textarea[name="message[body]"]', text: @message.body
      assert_select '.chat-image-input[disabled]'
      assert_select 'input[type="submit"][value="変更を保存"]'
      assert_select '.chat-edit-cancel[href=?]', conversation_path(@conversation, anchor: 'chat-reply')
    end
    assert_select '.chat-message__actions textarea', count: 0
    patch update_message_conversation_path(@conversation, message_id: @message.id), params: { message: { body: 'a' * 2001 } }
    assert_response :unprocessable_entity
    assert_select '#chat-reply textarea', text: 'a' * 2001
    assert_select '#chat-reply-title', text: 'メッセージを編集'
    assert_nil @message.reload.edited_at
  end

  test 'editing entry rejects peer expired and deleted messages' do
    sign_in @owner
    get conversation_path(@conversation, edit_message_id: @message.id)
    assert_response :redirect
    sign_out @owner
    sign_in @member
    travel_to @message.created_at + 12.hours do
      get conversation_path(@conversation, edit_message_id: @message.id)
      assert_response :redirect
    end
    @message.revise!('member', delete: true)
    get conversation_path(@conversation, edit_message_id: @message.id)
    assert_response :redirect
  end

  test 'deletion leaves a notice for both sides and webmaster and hides body and photo URL' do
    @message.update_column(:image, 'deleted-photo.enc')
    original = @message.body
    sign_in @member
    get messages_conversation_path(@conversation), as: :json
    version = response.parsed_body['history_version']
    assert_no_difference 'ChatMessage.count' do
      delete delete_message_conversation_path(@conversation, message_id: @message.id)
    end
    assert @message.reload.deleted_at
    assert_includes @message.preview_text, '削除しました'
    get messages_conversation_path(@conversation), as: :json
    assert_not_equal version, response.parsed_body['history_version']
    assert_not_includes response.parsed_body['html'], original
    [@member, @owner].each do |actor|
      sign_out @member
      sign_in actor
      get conversation_path(@conversation)
      assert_select "#chat-message-#{@message.id} .chat-deletion-notice", text: @message.deletion_notice
      assert_select "#chat-message-#{@message.id} .chat-message__actions", count: 0
      assert_not_includes response.body, original
      assert_select '.chat-image', count: 0
      assert_raises(ActiveRecord::RecordNotFound) { get chat_image_path(@conversation.public_id, @message.id) }
      sign_out actor
    end
    master = Webmaster.create!(id: 1, email: 'revision-master@example.test', password: 'test-password-123')
    sign_in master
    get super_admin_conversation_path(@conversation.public_id, page: 1)
    assert_response :success
    assert_includes response.body, @message.deletion_notice
    assert_select '.chat-revision', text: '削除済み'
    assert_not_includes response.body, original
    assert_raises(ActiveRecord::RecordNotFound) { get chat_image_path(@conversation.public_id, @message.id) }
  end

  test '12 hours is measured from original sending time and cannot be extended by edits' do
    sign_in @member
    travel_to @message.created_at + 12.hours - 1.second do
      patch update_message_conversation_path(@conversation, message_id: @message.id), params: { message: { body: '期限直前の訂正です。' } }
      assert_equal '期限直前の訂正です。', @message.reload.body
    end
    travel_to @message.created_at + 12.hours do
      get conversation_path(@conversation)
      assert_select '.chat-message__actions', count: 0
      patch update_message_conversation_path(@conversation, message_id: @message.id), params: { message: { body: '期限後' } }
      delete delete_message_conversation_path(@conversation, message_id: @message.id)
      assert_equal '期限直前の訂正です。', @message.reload.body
      assert_nil @message.deleted_at
    end
  end

  test 'peer outsider automatic messages and deleted messages cannot be revised' do
    sign_in @owner
    patch update_message_conversation_path(@conversation, message_id: @message.id), params: { message: { body: '改ざん' } }
    delete delete_message_conversation_path(@conversation, message_id: @message.id)
    assert_nil @message.reload.edited_at
    assert_nil @message.deleted_at
    sign_out @owner
    sign_in @other_member
    assert_raises(ActiveRecord::RecordNotFound) { delete delete_message_conversation_path(@conversation, message_id: @message.id) }
    sign_out @other_member
    sign_in @member
    automatic = @conversation.chat_messages.create!(sender_role: 'system', body: '自動案内')
    delete delete_message_conversation_path(@conversation, message_id: automatic.id)
    assert_nil automatic.reload.deleted_at
    delete delete_message_conversation_path(@conversation, message_id: @message.id)
    patch update_message_conversation_path(@conversation, message_id: @message.id), params: { message: { body: '復活' } }
    assert @message.reload.deleted_at
    assert_nil @message.edited_at
  end

  test 'invalid and unchanged edits leave the message and timestamps unchanged' do
    sign_in @member
    original = @message.body
    ['', 'a' * 2001, original].each do |body|
      patch update_message_conversation_path(@conversation, message_id: @message.id), params: { message: { body: body } }
      assert_equal original, @message.reload.body
      assert_nil @message.edited_at
    end
  end

  test 'deleted inquiries cannot become unanswered message penalties' do
    @message.revise!('member', delete: true)
    travel 4.days do
      assert_nil @conversation.no_reply_reportable_at
      assert_nil @conversation.unanswered_message_for('member')
      @conversation.update!(respond_check: 'NG')
      assert_not Conversation.reported_unanswered.exists?(@conversation.id)
    end
  end

  test 'spam edits return to moderation and deleted held posts cannot be released' do
    sign_in @member
    patch update_message_conversation_path(@conversation, message_id: @message.id), params: { message: { body: '性愛預約服務 https://t.me/spam-test LINE ID: bad' } }
    assert_equal 'held', @message.reload.moderation_status
    sign_out @member
    sign_in @owner
    get conversation_path(@conversation)
    assert_not_includes response.body, '性愛'
    sign_out @owner
    sign_in @member
    delete delete_message_conversation_path(@conversation, message_id: @message.id)
    assert_not @message.reload.moderate!('approve')
  end

  test 'owners can edit and delete and admin report and moderation screens show revision state' do
    accept_conversation
    reply = @conversation.chat_messages.where(sender_role: 'owner').sole
    sign_in @owner
    patch update_message_conversation_path(@conversation, message_id: reply.id), params: { message: { body: '日曜日に変更します。' } }
    assert reply.reload.edited_at
    sign_out @owner
    master = Webmaster.create!(id: 1, email: 'revision-master@example.test', password: 'test-password-123')
    report = @conversation.chat_reports.create!(chat_message: reply, reporter_role: 'member', reason: 'メッセージについて確認をお願いします。')
    sign_in master
    get super_admin_conversation_path(@conversation.public_id, page: 1)
    assert_select '.chat-revision', text: '編集済み'
    get super_admin_chat_report_path(report)
    assert_select '.chat-revision', text: '編集済み'
    sign_out master
    sign_in @owner
    delete delete_message_conversation_path(@conversation, message_id: reply.id)
    sign_out @owner
    sign_in master
    get super_admin_chat_report_path(report)
    assert_includes response.body, reply.reload.deletion_notice
    assert_not_includes response.body, '日曜日に変更します。'
    @message.update!(moderation_status: 'held', edited_at: Time.current)
    get super_admin_chat_moderations_path
    assert_select '.chat-revision', text: '編集済み'
    @message.revise!('member', delete: true)
    get super_admin_chat_moderations_path
    assert_select '.chat-revision', text: '削除済み'
    assert_select 'input[value="配信を許可"]', count: 0
  end

  test 'both organizers of practice matches may only revise their own messages' do
    source_owner = AdminUser.create!(email: 'revision-practice@example.test', password: 'test-password-123', email_verified_at: Time.current)
    source = @circle.dup
    source.update!(name: '練習相手サークル', admin_user: source_owner)
    practice = Conversation.for_circles!(@circle, source)
    outgoing = practice.send_message!('member', '練習試合を希望します。')
    incoming = practice.send_message!('owner', 'ぜひお願いします。')
    [[source_owner, outgoing, incoming], [@owner, incoming, outgoing]].each do |actor, own, peer|
      sign_in actor
      patch update_message_conversation_path(practice, message_id: own.id), params: { message: { body: '日程を訂正します。' } }
      assert own.reload.edited_at
      peer_deleted_at = peer.reload.deleted_at
      delete delete_message_conversation_path(practice, message_id: peer.id)
      peer_deleted_at ? assert_equal(peer_deleted_at, peer.reload.deleted_at) : assert_nil(peer.reload.deleted_at)
      delete delete_message_conversation_path(practice, message_id: own.id)
      assert own.reload.deleted_at
      sign_out actor
    end
  end

  private

  def sign_in(account)
    scope = account.is_a?(Member) ? :member : (account.is_a?(Webmaster) ? :webmaster : :admin_user)
    post public_send("#{scope}_session_path"), params: { scope => { email: account.email, password: 'test-password-123' } }
    assert_response :redirect
  end

  def sign_out(account)
    scope = account.is_a?(Member) ? :member : (account.is_a?(Webmaster) ? :webmaster : :admin_user)
    delete public_send("destroy_#{scope}_session_path")
    assert_response :redirect
  end
end
