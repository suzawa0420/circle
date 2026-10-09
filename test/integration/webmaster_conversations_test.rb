require 'test_helper'
require_relative '../support/chat_records'

class WebmasterConversationsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords
  setup do
    create_chat_records
    @master = Webmaster.create!(id: 1, email: 'webmaster@example.test', password: 'test-password-123')
  end

  test 'webmaster sees both profile cards without evaluation controls or read updates' do
    before = @conversation.reload.attributes
    login_master
    get super_admin_conversation_path(@conversation)
    assert_response :success
    assert_select '.chat-profiles .chat-profile', count: 2
    assert_select '.chat-profile--member a[href=?]', member_profile_path(@member)
    assert_select '.chat-profile--owner a[href=?]', circle_path(@circle)
    assert_select '.chat-profiles a.chat-profile__evaluate', count: 0
    assert_select '.chat-profile__evaluate--disabled', text: '評価は当事者のみ', count: 2
    assert_equal before, @conversation.reload.attributes
  end

  test 'webmaster conversation history links message URLs safely' do
    @conversation.send_message!('member', "https://example.test/contact?a=1&b=2\n<img src=x onerror=alert(1)>")
    login_master
    get super_admin_conversation_path(@conversation)
    assert_response :success
    assert_select '.wm-body a.message-url[href="https://example.test/contact?a=1&b=2"]', count: 1
    assert_select '.message-role--member', minimum: 1
    assert_select '.message-role--owner', minimum: 1
    assert_select '.wm-body img', count: 0
    assert_select '.wm-body [onerror]', count: 0
  end

  test 'only webmaster can read list and conversation without a report' do
    [super_admin_conversations_path, super_admin_conversation_path(@conversation)].each do |path|
      get path
      assert_redirected_to new_webmaster_session_path
    end
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    get super_admin_conversation_path(@conversation)
    assert_redirected_to new_webmaster_session_path
    post member_session_path, params: { member: { email: @member.email, password: 'test-password-123' } }
    get super_admin_conversations_path
    assert_redirected_to new_webmaster_session_path
    login_master
    get super_admin_conversations_path
    assert_response :success
    assert_includes response.body, @circle.name
    get super_admin_conversation_path(@conversation)
    assert_response :success
    assert_includes response.body, 'はじめまして。参加できますか？'
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_equal 'noindex, nofollow', response.headers['X-Robots-Tag']
    assert_not_includes response.body, 'googletagmanager'
  end

  test 'list shows one latest preview per conversation ordered by newest message and supports name search' do
    another = Conversation.for_member!(@circle, @other_member)
    another.send_message!('member', '別の参加者からの新しい問い合わせです。')
    login_master
    get super_admin_conversations_path
    assert_response :success
    links = css_select('.wm-actions a').map { |a| a['href'] }
    assert_equal [super_admin_conversation_path(another), super_admin_conversation_path(@conversation)], links
    get super_admin_conversations_path, params: { q: @other_member.nickname }
    assert_select '.wm-actions a', count: 1
    assert_includes response.body, '別の参加者からの新しい問い合わせです。'
    get super_admin_conversations_path, params: { q: '該当なし' }
    assert_includes response.body, '条件に一致する会話はありません。'
    get super_admin_conversations_path, params: { q: @circle.name }
    assert_select '.wm-actions a', count: 2
  end

  test 'reading does not change read receipts or notifications and sends nothing' do
    accept_conversation
    @conversation.update!(member_blocked: true)
    before = @conversation.reload.attributes
    login_master
    assert_no_difference('ChatMessage.count') do
      assert_no_difference('ActionMailer::Base.deliveries.size') { get super_admin_conversation_path(@conversation) }
    end
    assert_response :success
    assert_includes response.body, 'お問い合わせありがとうございます。'
    assert_includes response.body, 'ブロック中'
    assert_equal before, @conversation.reload.attributes
    assert_select 'form[action*="/message"]', count: 0
  end

  test 'latest page opens by default and older history can be paged in chronological order' do
    messages = 55.times.map { |i| { conversation_id: @conversation.id, sender_role: 'member', body: "履歴メッセージ #{i}", created_at: Time.current, updated_at: Time.current } }
    ChatMessage.insert_all!(messages)
    login_master
    get super_admin_conversation_path(@conversation)
    assert_select '.wm-message', count: 7
    assert_includes response.body, '履歴メッセージ 54'
    get super_admin_conversation_path(@conversation), params: { page: 1 }
    assert_select '.wm-message', count: 50
    assert_includes response.body, 'はじめまして。参加できますか？'
    assert_raises(ActiveRecord::RecordNotFound) { get super_admin_conversation_path('missing-public-id') }
  end

  test 'webmaster sees recipient read status on messages and the latest preview without changing it' do
    member_message = @conversation.chat_messages.where(sender_role: 'member').last
    @conversation.mark_read!('owner', through: member_message.id)
    accept_conversation
    login_master
    get super_admin_conversations_path
    assert_select '.wm-read-receipt', text: '参加者：未読'
    get super_admin_conversation_path(@conversation)
    assert_select '.wm-read-receipt', text: '主催者：既読'
    assert_select '.wm-read-receipt', text: '参加者：未読'
    assert_equal 0, @conversation.reload.member_read_message_id
    @conversation.mark_read!('member', through: @conversation.chat_messages.maximum(:id))
    get super_admin_conversations_path
    assert_select '.wm-read-receipt', text: '参加者：既読'
  end

  private
  def login_master
    post webmaster_session_path, params: { webmaster: { email: @master.email, password: 'test-password-123' } }
  end
end
