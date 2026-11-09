require 'test_helper'
require_relative '../support/chat_records'

class ConversationBlockingTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup { create_chat_records }

  test 'either participant blocks both senders and only clears their own flag' do
    accept_conversation
    [[@member, 'member'], [@owner, 'owner']].each do |actor, role|
      sign_in actor
      post block_conversation_path(@conversation), params: { owner_blocked: false, member_blocked: false }
      assert @conversation.reload["#{role}_blocked"]
      sign_out actor
    end
    [@member, @owner].each do |actor|
      sign_in actor
      assert_no_difference('ChatMessage.count') do
        post message_conversation_path(@conversation), params: { message: { body: '送信できません。' } }
      end
      assert_redirected_to conversation_path(@conversation)
      get messages_conversation_path(@conversation), as: :json
      assert_equal true, response.parsed_body['blocked']
      sign_out actor
    end
    sign_in @member
    delete block_conversation_path(@conversation)
    assert_not @conversation.reload.member_blocked?
    assert @conversation.owner_blocked?
    assert_raises(Conversation::NotAllowed) { @conversation.send_message!('member', 'まだ送れません。') }
    sign_out @member
    sign_in @owner
    delete block_conversation_path(@conversation)
    assert_not @conversation.reload.blocked?
    assert_difference('ChatMessage.count') { @conversation.send_message!('member', '解除後のメッセージです。') }
  end

  test 'new inquiry route cannot bypass a block on the existing conversation' do
    @conversation.set_blocked!('owner', blocked: true)
    sign_in @member
    assert_no_difference(['Conversation.count', 'ChatMessage.count']) do
      post user_conversations_path(@circle), params: { message: { body: 'お問い合わせを再送します。' } }
    end
    assert_redirected_to conversation_path(@conversation)
    assert @conversation.reload.owner_blocked?
  end

  test 'outsiders cannot change blocking with public or numeric identifiers' do
    sign_in @other_member
    [@conversation.public_id, @conversation.id].each do |identifier|
      [:post, :delete].each do |verb|
        assert_raises(ActiveRecord::RecordNotFound) { public_send(verb, block_conversation_path(identifier)) }
      end
    end
    assert_not @conversation.reload.blocked?
  end

  test 'blocking cancels pending message and review notifications even when immediately undone' do
    due_attributes = %w[member owner].flat_map { |role| ["#{role}_notification_due_at", "#{role}_review_notification_due_at"] }.to_h { |key| [key, 1.minute.ago] }
    @conversation.update!(due_attributes)
    @conversation.set_blocked!('member', blocked: true)
    @conversation.set_blocked!('member', blocked: false)
    due_attributes.each_key { |key| assert_nil @conversation.reload[key] }
    assert_no_difference('ActionMailer::Base.deliveries.size') do
      %w[member owner].each do |role|
        ChatMaintenance.deliver_pending(@conversation, role)
        ChatMaintenance.deliver_review_invitation(@conversation, role)
      end
    end
  end

  test 'history and both evaluation rights survive blocking' do
    accept_conversation
    ids = @conversation.chat_messages.pluck(:id)
    @conversation.set_blocked!('member', blocked: true)
    [[@member, member_evaluation], [@owner, owner_evaluation]].each do |actor, evaluation|
      sign_in actor
      get conversation_path(@conversation)
      assert_response :success
      assert_select '#chat-reply form', count: 0
      put review_conversation_path(@conversation), params: { evaluation: evaluation }
      sign_out actor
    end
    assert_equal ids, @conversation.chat_messages.pluck(:id)
    assert_equal 2, @conversation.conversation_reviews.count
    assert @conversation.reload.reviews_published_at
  end

  test 'edits reactions and held approvals cannot bypass blocking but deletion and spam review remain possible' do
    delivered = @conversation.chat_messages.find_by!(sender_role: 'member')
    held = @conversation.send_message!('member', '性愛預約服務')
    assert_equal 'held', held.moderation_status
    @conversation.set_blocked!('owner', blocked: true)
    assert_not delivered.editable_by?('member')
    assert delivered.changeable_by?('member')
    assert_raises(Conversation::NotAllowed) { delivered.revise!('member', body: '新しい本文です。') }
    assert_raises(Conversation::NotAllowed) { delivered.set_reaction!('owner', 'thanks') }
    assert_raises(Conversation::NotAllowed) { held.moderate!('approve') }
    assert_equal 'held', held.reload.moderation_status
    assert_nil held.released_at
    assert_nil @conversation.reload.owner_notification_due_at
    assert delivered.revise!('member', delete: true)
    assert delivered.reload.deleted_at
    assert held.moderate!('spam')
    assert_equal 'spam', held.reload.moderation_status
  end

  test 'held approval becomes possible only after blocking is fully cleared' do
    held = @conversation.send_message!('member', '性愛預約服務')
    @conversation.set_blocked!('member', blocked: true)
    @conversation.set_blocked!('owner', blocked: true)
    @conversation.set_blocked!('member', blocked: false)
    assert_raises(Conversation::NotAllowed) { held.moderate!('approve') }
    @conversation.set_blocked!('owner', blocked: false)
    assert held.moderate!('approve')
    assert_equal 'approved', held.reload.moderation_status
    assert @conversation.reload.owner_notification_due_at
  end

  test 'practice match source organizer controls only the member side block' do
    source_owner = AdminUser.create!(email: 'blocking-practice@example.test', password: 'test-password-123', email_verified_at: Time.current)
    source = @circle.dup
    source.admin_user = source_owner
    source.save!
    conversation = Conversation.for_circles!(@circle, source)
    conversation.send_message!('member', '練習試合についてご相談です。')
    sign_in source_owner
    post block_conversation_path(conversation)
    assert conversation.reload.member_blocked?
    assert_not conversation.owner_blocked?
    sign_out source_owner
    sign_in @owner
    delete block_conversation_path(conversation)
    assert conversation.reload.member_blocked?
    assert_no_difference('ChatMessage.count') do
      post message_conversation_path(conversation), params: { message: { body: '送信できません。' } }
    end
  end
  test 'repeated blocking is idempotent and does not affect another conversation' do
    other = Conversation.for_member!(@circle, @other_member)
    before = other.attributes
    sign_in @member
    2.times { post block_conversation_path(@conversation) }
    assert @conversation.reload.member_blocked?
    assert_not @conversation.owner_blocked?
    assert_equal before, other.reload.attributes
    assert_difference(-> { other.chat_messages.where(sender_role: 'member').count }) { other.send_message!('member', 'こちらは送信できます。') }
    2.times { delete block_conversation_path(@conversation) }
    assert_not @conversation.reload.blocked?
  end

  test 'stale edit requests and direct patches cannot deliver changed text after blocking' do
    message = @conversation.chat_messages.find_by!(sender_role: 'member')
    original = message.body
    sign_in @member
    get conversation_path(@conversation), params: { edit_message_id: message.id }
    assert_response :success
    @conversation.set_blocked!('owner', blocked: true)
    patch update_message_conversation_path(@conversation, message_id: message.id), params: { message: { body: 'ブロック後の変更です。' } }
    assert_redirected_to conversation_path(@conversation)
    assert_equal original, message.reload.body
    assert_nil message.edited_at
    get conversation_path(@conversation), params: { edit_message_id: message.id }
    assert_redirected_to conversation_path(@conversation)
    delete delete_message_conversation_path(@conversation, message_id: message.id)
    assert message.reload.deleted_at
  end

  test 'superadmin approval redirects without releasing a blocked held message' do
    held = @conversation.send_message!('member', '性愛預約服務')
    @conversation.set_blocked!('owner', blocked: true)
    master = Webmaster.create!(id: 1, email: 'blocking-master@example.test', password: 'test-password-123')
    post webmaster_session_path, params: { webmaster: { email: master.email, password: 'test-password-123' } }
    assert_response :redirect
    patch super_admin_chat_moderation_path(held), params: { decision: 'approve' }
    assert_redirected_to super_admin_chat_moderations_path
    assert flash[:alert].present?
    assert_equal 'held', held.reload.moderation_status
    assert_nil held.released_at
    assert_nil @conversation.reload.owner_notification_due_at
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
