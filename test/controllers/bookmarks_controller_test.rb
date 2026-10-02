require 'test_helper'
require_relative '../support/chat_records'

class BookmarksControllerTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup { create_chat_records }

  test 'guest navigation offers search, account choice and menu with registration for saving' do
    get circle_path(@circle)
    assert_response :success
    assert_select '.mobile-bottom-nav > a', count: 2
    assert_select '.mobile-bottom-nav > button', count: 1
    assert_select ".mobile-bottom-nav a[href='#{circles_path}']", text: 'サークル検索'
    assert_select ".mobile-bottom-nav a[href='#{login_path}']", text: '無料登録・ログイン'
    assert_select ".mobile-circle-summary__identity a[href='#{new_member_registration_path}']", text: '保存'
    assert_select ".bookmark_btn_wrap a[href='#{new_member_registration_path}']"
    assert_select '.mobile-circle-save[data-remote]', count: 0
    get login_path
    assert_select "a[href='#{new_admin_user_registration_path}']", text: '無料で新規登録'
    assert_select "a[href='#{new_member_registration_path}']", text: '無料で新規登録'
  end

  test 'guest bookmark requests go to free participant registration without saving' do
    assert_no_difference('Bookmark.count') do
      post user_bookmarks_path(@circle)
      assert_redirected_to new_member_registration_path
    end
  end

  test 'participant can repeatedly save and unsave with synchronized header and body buttons' do
    post member_session_path, params: { member: { email: @member.email, password: 'test-password-123' } }
    assert_response :redirect
    2.times do
      assert_difference('Bookmark.count', 1) { post user_bookmarks_path(@circle), xhr: true }
      assert_response :success
      assert_includes response.body, "#mobile-circle-bookmark-#{@circle.id}"
      assert_includes response.body, 'replaceWith'
      get circle_path(@circle)
      assert_select '.mobile-circle-save[aria-pressed=true][data-method=delete]', text: '保存済み'
      assert_select '.bookmark_btn_wrap a', text: '保存済み'

      assert_difference('Bookmark.count', -1) { delete user_bookmarks_path(@circle), xhr: true }
      assert_response :success
      assert_includes response.body, "#mobile-circle-bookmark-#{@circle.id}"
      get circle_path(@circle)
      assert_select '.mobile-circle-save[aria-pressed=false][data-method=post]', text: '保存'
      assert_select '.bookmark_btn_wrap a', text: '保存'
    end
  end
end
