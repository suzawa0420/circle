require 'test_helper'
require_relative '../support/chat_records'

class MemberInquiryLimitTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    travel_to Time.find_zone!('Asia/Tokyo').local(2026, 11, 12, 12)
    create_chat_records
    @sequence = 0
    sign_in @member
  end

  teardown { travel_back }

  test 'fifth distinct circle succeeds and sixth is rejected without saving a thread' do
    4.times { post user_conversations_path(new_circle), params: { message: { body: '活動について教えてください。' } } }
    assert_equal 5, quota.used
    target = new_circle
    assert_no_difference ['Conversation.count', 'ChatMessage.count'] do
      post user_conversations_path(target), params: { message: { body: '参加したいです。' } }
    end
    assert_redirected_to conversations_path
    assert_equal MemberInquiryLimit::MESSAGE, flash[:alert]
  end

  test 'existing conversations permit both create endpoint and reply endpoint at the limit' do
    fill_quota
    assert_difference 'ChatMessage.where(sender_role: "member").count', 2 do
      post user_conversations_path(@circle), params: { message: { body: '日程を確認したいです。' } }
      post message_conversation_path(@conversation), params: { message: { body: 'ありがとうございます。' } }
    end
    assert_equal 5, quota.used
    sign_out @member
    sign_in @owner
    assert_difference 'ChatMessage.where(sender_role: "owner").count' do
      post message_conversation_path(@conversation), params: { message: { body: 'ご参加お待ちしています。' } }
    end
  end

  test 'empty previously created conversations cannot bypass model or reply endpoint' do
    empty = Conversation.for_member!(new_circle, @member)
    empty.update_columns(created_at: 2.days.ago)
    empty.chat_messages.create!(sender_role: 'system', body: '案内です。')
    fill_quota
    assert_raises(Conversation::NotAllowed) { empty.send_message!('member', '参加したいです。') }
    assert_no_difference 'ChatMessage.count' do
      post message_conversation_path(empty), params: { message: { body: '参加したいです。' } }
    end
    assert_equal MemberInquiryLimit::MESSAGE, flash[:alert]
  end

  test 'held and spam and deleted first messages still consume quota' do
    @conversation.chat_messages.where(sender_role: 'member').update_all(moderation_status: 'spam', deleted_at: Time.current)
    held = Conversation.for_member!(new_circle, @member).send_message!('member', '性愛預約服務')
    assert_equal 'held', held.moderation_status
    3.times { Conversation.for_member!(new_circle, @member).send_message!('member', '参加したいです。') }
    assert_equal 5, quota.used
    assert_raises(Conversation::NotAllowed) { Conversation.for_member!(new_circle, @member).send_message!('member', '参加したいです。') }
  end

  test 'invalid and blocked submissions do not consume quota' do
    empty = Conversation.for_member!(new_circle, @member)
    assert_raises(ActiveRecord::RecordInvalid) { empty.send_message!('member', '') }
    assert_equal 1, quota.used
    empty.set_blocked!('owner', blocked: true)
    assert_raises(Conversation::NotAllowed) { empty.send_message!('member', '参加したいです。') }
    assert_equal 1, quota.used
  end

  test 'quota resets exactly at Japan midnight even when process time zone is UTC' do
    fill_quota
    Time.use_zone('UTC') do
      travel_to Time.utc(2026, 11, 12, 14, 59, 59)
      assert_equal 0, quota.remaining
      travel_to Time.utc(2026, 11, 12, 15, 0, 0)
      assert_equal 5, quota.remaining
      @conversation.send_message!('member', '前日からの続きです。')
      assert_equal 0, quota.used
      Conversation.for_member!(new_circle, @member).send_message!('member', '参加したいです。')
      assert_equal 1, quota.used
    end
  end

  test 'other members and organizer practice matches do not consume member quota' do
    fill_quota
    Conversation.for_member!(new_circle, @other_member).send_message!('member', '参加したいです。')
    assert_equal 1, MemberInquiryLimit.new(@other_member).used
    other_owner = AdminUser.create!(email: 'limit-practice@example.test', password: 'test-password-123', email_verified_at: Time.current)
    source = new_circle
    source.update!(admin_user: other_owner)
    practice = Conversation.for_circles!(@circle, source)
    practice.send_message!('member', '練習試合をお願いします。')
    assert_equal 5, quota.used
  end

  test 'remaining count appears on inbox and thread and full quota disables only new circle form' do
    get conversations_path
    assert_select '.chat-inquiry-limit strong', text: '本日、新しく問い合わせできるサークル：あと4件 / 5件'
    get conversation_path(@conversation)
    assert_select '.chat-inquiry-limit', count: 1
    fill_quota
    get new_user_conversation_path(new_circle)
    assert_select '.chat-inquiry-limit strong', text: /あと0件 \/ 5件/
    assert_select 'input[type=submit][disabled][value="問い合わせを送信"]'
    get conversation_path(@conversation)
    assert_select '#chat-reply input[type=submit]:not([disabled])'
    sign_out @member
    sign_in @owner
    get conversations_path
    assert_select '.chat-inquiry-limit', count: 0
    get conversation_path(@conversation)
    assert_select '.chat-inquiry-limit', count: 0
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

  def quota = MemberInquiryLimit.new(@member)

  def fill_quota
    4.times { Conversation.for_member!(new_circle, @member).send_message!('member', '参加したいです。') }
  end

  def new_circle
    @sequence += 1
    circle = @circle.dup
    circle.name = "問い合わせ検証サークル#{@sequence}"
    circle.save!
    circle
  end
end
