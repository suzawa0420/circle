require 'test_helper'
require_relative '../support/chat_records'

class MobileNavigationTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup { create_chat_records }

  test 'owner navigation prioritizes messages, schedules and blog posting' do
    login(@owner)
    get conversations_path
    assert_select '.mobile-bottom-nav > a', count: 3
    assert_select '.mobile-bottom-nav > button', count: 1
    assert_select '.mobile-bottom-nav > a:nth-child(1)', text: /メッセージ/
    assert_select ".mobile-bottom-nav > a:nth-child(2)[href='#{user_schedules_path(@circle)}']", text: 'スケジュール'
    assert_select ".mobile-bottom-nav > a:nth-child(3)[href='#{new_circle_blog_path(@circle)}']", text: 'ブログ'
    assert_select '.mobile-bottom-nav__badge', text: '1'
    get conversation_path(@conversation)
    get conversations_path
    assert_select '.mobile-bottom-nav__badge', count: 0
    assert_select '.mobile-bottom-nav a[aria-label="メッセージ（未読なし）"]'
  end

  test 'participant navigation links to search, messages and saved circles with only incoming unread threads' do
    login(@member)
    get conversations_path
    assert_select ".mobile-bottom-nav > a:nth-child(1)[href='#{circles_path}']", text: 'サークル検索'
    assert_select '.mobile-bottom-nav > a:nth-child(2)', text: 'メッセージ'
    assert_select ".mobile-bottom-nav > a:nth-child(3)[href='#{member_path(@member, anchor: 'favorites')}']", text: 'お気に入り'
    assert_select '.mobile-bottom-nav > button', text: 'メニュー'
    assert_select '.mobile-bottom-nav__badge', count: 0
    accept_conversation
    @conversation.send_message!('owner', '追加のお知らせです。')
    get conversations_path
    assert_select '.mobile-bottom-nav__badge', text: '1'
    get conversation_path(@conversation)
    get conversations_path
    assert_select '.mobile-bottom-nav__badge', count: 0
  end

  test 'owner links follow the current owned circle and unread count covers all owned circles' do
    second = User.create!(@circle.attributes.except('id', 'created_at', 'updated_at', 'unique_id').merge(name: '別の管理サークル'))
    Conversation.for_member!(second, @member).send_message!('member', 'こちらにも参加希望です。')
    outsider = AdminUser.create!(email: 'navigation-outsider@example.test', password: 'test-password-123', email_verified_at: Time.current)
    foreign = User.create!(@circle.attributes.except('id', 'created_at', 'updated_at', 'unique_id').merge(admin_user_id: outsider.id, name: '他の主催者のサークル'))
    Conversation.for_member!(foreign, @member).send_message!('member', '別の主催者への問い合わせです。')
    login(@owner)
    get user_schedules_path(second)
    assert_select ".mobile-bottom-nav a[href='#{user_schedules_path(second)}']"
    assert_select ".mobile-bottom-nav a[href='#{new_circle_blog_path(second)}']"
    assert_select '.mobile-bottom-nav__badge', text: '2'
    get circle_path(foreign)
    assert_select ".mobile-bottom-nav a[href='#{user_schedules_path(foreign)}']", count: 0
    assert_select ".mobile-bottom-nav a[href='#{user_schedules_path(@circle)}']"
  end

  private

  def login(account)
    path = account.is_a?(Member) ? member_session_path : admin_user_session_path
    key = account.is_a?(Member) ? :member : :admin_user
    post path, params: { key => { email: account.email, password: 'test-password-123' } }
    assert_response :redirect
  end
end
