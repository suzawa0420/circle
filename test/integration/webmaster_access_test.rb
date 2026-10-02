require 'test_helper'
require_relative '../support/chat_records'

class WebmasterAccessTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    @master = Webmaster.create!(id: 1, email: 'webmaster@example.test', password: 'test-password-123')
  end

  test 'dedicated login opens dashboard and logout removes management access' do
    get new_webmaster_session_path
    assert_response :success
    assert_select 'h1', text: 'ウェブマスターログイン'
    assert_select 'a[href*="sign_up"]', count: 0
    login_master
    assert_redirected_to webmaster_path
    follow_redirect!
    assert_response :success
    assert_select "a[href='#{super_admin_circles_path}']"
    assert_select "a[href='#{super_admin_chat_reports_path}']"
    assert_not_includes response.body, 'googletagmanager'
    assert_includes response.headers['Cache-Control'], 'no-store'
    delete destroy_webmaster_session_path
    get webmaster_path
    assert_redirected_to new_webmaster_session_path
  end

  test 'ordinary participant and legacy organizer id one cannot access management' do
    get webmaster_path
    assert_redirected_to new_webmaster_session_path
    post member_session_path, params: { member: { email: @member.email, password: 'test-password-123' } }
    get super_admin_circles_path
    assert_redirected_to new_webmaster_session_path
    legacy = AdminUser.find_by(id: 1) || AdminUser.create!(id: 1, email: 'circlebook26@gmail.com', password: 'test-password-123')
    legacy.update!(email: 'circlebook26@gmail.com', moderator: true)
    post admin_user_session_path, params: { admin_user: { email: legacy.email, password: 'test-password-123' } }
    [webmaster_path, super_admin_circles_path, super_admin_chat_reports_path, invalid_emails_path, account_blocks_path, db_keywords_path, db_validation_errors_path, admin_user_list_path].each do |path|
      get path
      assert_response :redirect
      assert_not_equal 200, response.status
    end
    assert_no_difference('AdminUser.count') { delete super_admin_circle_path(@owner) }
    patch user_path(@circle), params: { user: { name: '旧IDによる不正な編集' } }
    assert_not_equal '旧IDによる不正な編集', @circle.reload.name
    patch "/users/#{@circle.id}/admin_user_update", params: { admin_user: { check: 3 } }
    assert_not_equal 3, @owner.reload.check
    post webmaster_session_path, params: { webmaster: { email: legacy.email, password: 'test-password-123' } }
    assert_not_equal webmaster_path, response.location&.delete_prefix('http://www.example.com')
  end

  test 'master without organizer session can use every dashboard destination and edit a circle' do
    login_master
    [webmaster_path, super_admin_circles_path, super_admin_chat_reports_path, invalid_emails_path, account_blocks_path, db_keywords_path, db_validation_errors_path, admin_user_list_path, super_admin_places_path, places_count_path, new_place_path].each do |path|
      get path
      assert_response :success, path
    end
    get edit_user_path(@circle)
    assert_response :success
    assert_select 'select[name="user[ng_account]"]'
    patch user_path(@circle), params: { user: { name: '運営による更新', ng_account: 'NG' } }
    assert_response :redirect
    assert_equal '運営による更新', @circle.reload.name
    assert_equal 'NG', @circle.ng_account
    patch super_admin_circle_moderation_path(@circle), params: { moderation_status: 'blocked' }
    assert_equal 'blocked', @circle.reload.moderation_status
    get circle_path(@circle)
    assert_response :success
    patch "/users/#{@circle.id}/admin_user_update", params: { admin_user: { check: 3 } }
    assert_equal 3, @owner.reload.check
  end

  test 'master can moderate blogs and questions but cannot impersonate a chat owner' do
    blog = Blog.create!(user: @circle, title: '活動報告', content: '活動の記録です。' * 20)
    question = Question.create!(user: @circle, content: '参加できますか？')
    login_master
    get edit_circle_blog_path(@circle, blog)
    assert_response :success
    delete circle_blog_path(@circle, blog)
    assert_not Blog.exists?(blog.id)
    patch user_question_path(@circle, question), params: { question: { answer: '運営の回答' } }
    assert_equal '運営の回答', question.reload.answer
    assert_no_difference('ChatMessage.count') do
      post message_conversation_path(@conversation), params: { message: { body: '代理返信' } }
    end
  end

  test 'organizer profile update cannot change moderation status' do
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    patch "/users/#{@circle.id}/edit3", params: { admin_user: { nickname: '主催者', check: 3 } }
    assert_equal '主催者', @owner.reload.nickname
    assert_not_equal 3, @owner.check
  end

  test 'webmaster registration and password recovery are not exposed' do
    assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path('/webmaster/sign_up', method: :get) }
    assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path('/webmaster', method: :post) }
    assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path('/webmaster/password', method: :post) }
    assert_not Webmaster.new(id: 2, email: 'other@example.test', password: 'test-password-123').valid?
    assert_raises(ActiveRecord::StatementInvalid) do
      Webmaster.transaction(requires_new: true) do
        Webmaster.insert_all!([{ id: 2, email: 'other@example.test', encrypted_password: 'not-a-password', created_at: Time.current, updated_at: Time.current }])
      end
    end
  end

  test 'failed passwords lock the webmaster account temporarily' do
    10.times do
      post webmaster_session_path, params: { webmaster: { email: @master.email, password: 'wrong-password' } }
    end
    assert @master.reload.access_locked?
    login_master
    get webmaster_path
    assert_redirected_to new_webmaster_session_path
    travel 31.minutes do
      login_master
      assert_redirected_to webmaster_path
    end
  end

  private
  def login_master
    post webmaster_session_path, params: { webmaster: { email: @master.email, password: 'test-password-123' } }
  end
end
