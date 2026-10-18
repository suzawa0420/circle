require 'test_helper'
require_relative '../support/chat_records'

class OrganizerProfileEditTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
  end

  test 'profile editing requires an organizer login' do
    get edit_organizer_profile_path
    assert_redirected_to new_admin_user_session_path
    patch organizer_profile_path, params: { admin_user: { nickname: '変更不可' } }
    assert_redirected_to new_admin_user_session_path
    assert_nil @owner.reload.nickname
  end

  test 'dashboard links to the common profile before logout and omits legacy contacts' do
    legacy_contact = @circle.user_contacts.create!(name: '参加希望者', mail: 'legacy@example.test', message: '参加したいです。', respond_check: 'NG')
    login_owner
    get "/users/#{@circle.id}/mypage"
    assert_response :success
    assert_select '.dashboard-account-settings .dashboard-action-list > a:first-child' do
      assert_select "[href='#{edit_organizer_profile_path}']"
      assert_select 'strong', text: '主催者プロフィール編集'
    end
    assert_select "a[href='/users/#{@circle.id}/contact_list']", count: 0
    assert UserContact.exists?(legacy_contact.id)
  end

  test 'standalone form preserves private setting without circle editing steps' do
    @owner.update!(open: 2)
    login_owner
    get edit_organizer_profile_path
    assert_response :success
    assert_select "form[action='#{organizer_profile_path}'][enctype='multipart/form-data']"
    assert_select 'input[name="admin_user[open]"][value="2"][checked]'
    assert_select 'input[name="admin_user[open]"][value="1"][checked]', count: 0
    assert_select 'input[name="admin_user[nickname]"]'
    assert_select 'input[name="admin_user[image_profile]"]'
    assert_select 'select[name="admin_user[age]"]'
    assert_select 'select[name="admin_user[prefecture_id]"]'
    assert_select 'textarea[name="admin_user[profile]"]'
    assert_select "a[href='/users/#{@circle.id}/edit2']", count: 0
  end

  test 'updates only the signed in organizer and preserves login and moderation settings' do
    other = AdminUser.create!(email: 'profile-other@example.test', password: 'test-password-123', nickname: '別の主催者')
    @owner.update!(gender: 1)
    login_owner
    patch organizer_profile_path, params: { id: other.id, admin_user: {
      id: other.id, nickname: '新しい主催者', profile: '週末に活動しています', open: 2, age: '30代',
      prefecture_id: @circle.prefecture_id, gender: 2, email: 'changed@example.test', check: 3
    } }
    assert_redirected_to edit_organizer_profile_path
    @owner.reload
    assert_equal '新しい主催者', @owner.nickname
    assert_equal '週末に活動しています', @owner.profile
    assert_equal 2, @owner.open
    assert_equal '30代', @owner.age
    assert_equal @circle.prefecture_id, @owner.prefecture_id
    assert_equal '1', @owner.gender
    assert_equal 'chat-owner@example.test', @owner.email
    assert_nil @owner.check
    assert_equal '別の主催者', other.reload.nickname
  end

  test 'invalid input displays errors and does not save' do
    login_owner
    patch organizer_profile_path, params: { admin_user: { nickname: 'あ' * 17 } }
    assert_response :unprocessable_entity
    assert_select '.form-error_message'
    assert_nil @owner.reload.nickname
  end

  test 'circle editing step three still renders and updates the shared form' do
    login_owner
    get "/users/#{@circle.id}/edit3"
    assert_response :success
    assert_select "form[action='/users/#{@circle.id}/edit3']"
    patch "/users/#{@circle.id}/edit3", params: { admin_user: { nickname: '編集ステップから' } }
    assert_redirected_to circle_path(@circle)
    assert_equal '編集ステップから', @owner.reload.nickname
  end

  private

  def login_owner
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
  end
end
