require 'test_helper'
require_relative '../support/chat_records'

class SiteDesignTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup { create_chat_records }

  test 'owner dashboard renders Lucide actions including additional circle registration' do
    login(@owner)
    get "/users/#{@circle.id}/mypage"
    assert_response :success
    assert_select '.dashboard-action svg.cb-icon--plus', count: 1
    assert_select '.dashboard-action svg.cb-icon', minimum: 5
    assert_select '.fa', count: 0
  end

  test 'public pages share the design scope and a Japanese document language' do
    [root_path, circles_path, '/blogs', '/matches', '/places', '/about', '/faq', '/rules', '/privacypolicy', '/login'].each do |path|
      get path
      assert_response :success, path
      assert_select 'html[lang=ja]', count: 1
      assert_select 'body.cb-site', count: 1
      assert_select 'h1', minimum: 1
    end
  end

  test 'search sorting preserves the keyword and drops a stale page number' do
    get circles_search_index_path, params: { q: @circle.name, sort: '2', page: '1' }
    assert_response :success
    assert_select '.cb-sort [aria-current=true]', text: '人気順'
    assert_select '.cb-sort a' do |links|
      links.each do |link|
        query = Rack::Utils.parse_nested_query(URI.parse(link['href']).query)
        assert_equal @circle.name, query['q']
        assert_nil query['page']
      end
    end
    assert_select 'input[name=q][aria-label]'
    assert_select 'select[name=event_select][aria-label]'
  end

  test 'circle editing has one named heading and retains the circle switcher' do
    login(@owner)
    get edit_user_path(@circle)
    assert_response :success
    assert_select 'h1', count: 1, text: 'サークルの基本情報'
    assert_select '.management-circle-trigger'
    assert_select 'form input[name="user[name]"]'
  end

  test 'question edit opens the answer form on its detail page' do
    question = @circle.questions.create!(content: '一人でも参加できますか？')
    login(@owner)
    get edit_user_question_path(@circle, question)
    assert_redirected_to user_question_path(@circle, question)
    follow_redirect!
    assert_response :success
    assert_select 'h1', count: 1, text: question.content
    assert_select 'textarea[name="question[answer]"]'
  end
  test 'participant entry points have an explicit role without recoloring organizer entry points' do
    get '/login'
    assert_response :success
    assert_select '.login-choice__card.cb-participant #participant-login-title', count: 1
    assert_select '.login-choice__card.cb-participant #organizer-login-title', count: 0
    get circle_path(@circle)
    assert_response :success
    assert_select '.mobile-circle-save.cb-participant', minimum: 1
    assert_select '.mobile-circle-summary__image--empty', text: 'チ'
    assert_select '.circle-avatar--empty.profile_imege', text: 'チ'
  end

  test 'participant chat scope and author identities remain distinct' do
    accept_conversation
    post member_session_path, params: { member: { email: @member.email, password: 'test-password-123' } }
    get conversation_path(@conversation)
    assert_response :success
    assert_select '.chat-shell.cb-participant', count: 1
    assert_select '.chat-avatar--owner', minimum: 1
    assert_select '.chat-message--member', minimum: 1
    assert_select '.message-role--member', minimum: 1
    assert_select '.message-role--owner', minimum: 1
    assert_select '.chat-message--owner', minimum: 1
    delete destroy_member_session_path
    login(@owner)
    get conversation_path(@conversation)
    assert_response :success
    assert_select '.chat-shell.cb-participant', count: 0
    assert_select '.chat-avatar--member', minimum: 1
  end

  test 'platform notices are separate from organizer automatic guidance' do
    login(@owner)
    get conversation_path(@conversation)
    assert_response :success
    assert_select '#chat-acceptance-status.cb-system-notice .cb-system-notice__label', text: 'システム通知'
    assert_select '.inquiry-guidance__message.cb-system-notice', count: 0
    get admin_user_email_verification_path
    assert_response :success
    assert_select '.cb-system-panel', count: 1
    assert_select '.cb-system-notice', minimum: 1
  end

  private

  def login(owner)
    post admin_user_session_path, params: { admin_user: { email: owner.email, password: 'test-password-123' } }
    assert_response :redirect
  end

end
