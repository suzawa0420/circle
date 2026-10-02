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
    assert_select ".mobile-bottom-nav a[href='#{user_schedules_path(second)}']"
  end

  test 'circle switcher shows only owned circles and remembers selection across management pages' do
    second = User.create!(@circle.attributes.except('id', 'created_at', 'updated_at', 'unique_id').merge(name: '切り替え先のサークル'))
    outsider = AdminUser.create!(email: 'switch-outsider@example.test', password: 'test-password-123', email_verified_at: Time.current)
    foreign = User.create!(@circle.attributes.except('id', 'created_at', 'updated_at', 'unique_id').merge(admin_user_id: outsider.id, name: '表示しない他人のサークル'))
    login(@owner)
    get new_circle_blog_path(@circle)
    assert_response :success
    assert_select '.mobile-bottom-nav > button:first-child.mobile-circle-trigger', text: /#{@circle.name}/
    assert_select '#mobile-circle-dialog a', count: 2
    assert_select "#mobile-circle-dialog a[aria-current=true][href='#{new_circle_blog_path(@circle)}']", text: /選択中/
    assert_select "#mobile-circle-dialog a[href='#{new_circle_blog_path(second)}']"
    assert_select '#mobile-circle-dialog', text: /#{foreign.name}/, count: 0

    get new_circle_blog_path(second)
    assert_select '.mobile-circle-trigger', text: /#{second.name}/
    get edit_admin_user_registration_path
    assert_select '.mobile-circle-trigger', text: /#{second.name}/
    assert_select ".mobile-site-heading a[href='/users/#{second.id}/mypage']"
    assert_select "#mobile-circle-dialog a[aria-current=true][href='/users/#{second.id}/mypage']"
    get user_questions_path(second)
    assert_select "#mobile-circle-dialog a[href='#{user_questions_path(@circle)}']"
    get user_reviews_path(second)
    assert_select "#mobile-circle-dialog a[href='#{user_reviews_path(@circle)}']"
    get conversations_path
    assert_select '.mobile-circle-trigger', count: 0
    assert_select '#mobile-circle-dialog', count: 0
  end

  test 'management headings show the selected circle and share its chooser across editing sections' do
    second = User.create!(@circle.attributes.except('id', 'created_at', 'updated_at', 'unique_id').merge(name: '作業中のサークル'))
    login(@owner)
    [user_schedules_path(second), new_circle_blog_path(second), user_questions_path(second), user_reviews_path(second)].each do |path|
      get path
      assert_response :success
      assert_select 'h1.management-heading', count: 1
      assert_select '.management-circle-trigger[aria-controls="mobile-circle-dialog"]', text: /#{second.name}/
      assert_select '.management-circle-trigger .mobile-circle-avatar', count: 1
      assert_select 'select[name="user_select"]', count: 0
      assert_select '#mobile-circle-dialog', count: 1
    end
    get new_user_schedule_path(second)
    assert_response :success
    assert_select ".mobile-circle-list__item[href='#{new_user_schedule_path(@circle)}']"
    get circle_path(second)
    assert_select '.management-circle-trigger', count: 0
  end

  private

  def login(account)
    path = account.is_a?(Member) ? member_session_path : admin_user_session_path
    key = account.is_a?(Member) ? :member : :admin_user
    post path, params: { key => { email: account.email, password: 'test-password-123' } }
    assert_response :redirect
  end
end
