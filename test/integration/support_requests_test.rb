require 'test_helper'
require_relative '../support/chat_records'

class SupportRequestsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    @master = Webmaster.create!(id: 1, email: 'webmaster@example.test', password: 'test-password-123')
  end

  test 'category answers precede form and anonymous users can report login problems without mail' do
    get new_support_request_path(category: 'account')
    assert_response :success
    assert_select "a[href='#{help_article_path('login')}']"
    assert_select 'textarea', count: 0
    get new_support_request_path(category: 'account', step: 'form')
    token = css_select('form[action="/support"] input[name=spam_form_token]').first['value']
    assert_difference('SupportRequest.count', 1) do
      assert_no_difference('ActionMailer::Base.deliveries.size') do
        post support_requests_path, params: request_params(token)
      end
    end
    assert_redirected_to support_thanks_path
    assert_equal 'ログインできません。再設定も試しました。', SupportRequest.last.body
    assert_nil SupportRequest.last.member_id
    follow_redirect!
    assert_includes response.body, '送信を受け付けました'
    assert_not_includes response.body, 'googletagmanager'
    assert_includes response.headers['Cache-Control'], 'no-store'
  end

  test 'invalid submissions keep entered content and forged tokens or honeypots save nothing' do
    get new_support_request_path(step: 'form')
    token = css_select('form[action="/support"] input[name=spam_form_token]').first['value']
    invalid = request_params(token)
    invalid[:support_request][:body] = '短い'
    assert_no_difference('SupportRequest.count') { post support_requests_path, params: invalid }
    assert_response :unprocessable_entity
    assert_select 'textarea', text: '短い'
    assert_no_difference('SupportRequest.count') { post support_requests_path, params: request_params('forged') }
    assert_response :unprocessable_entity
    assert_no_difference('SupportRequest.count') { post support_requests_path, params: request_params(token).merge(contact_website: 'spam') }
  end

  test 'incomplete owner accounts can still reach help and support' do
    owner = AdminUser.create!(email: 'incomplete@example.test', password: 'test-password-123')
    post admin_user_session_path, params: { admin_user: { email: owner.email, password: 'test-password-123' } }
    get faq_path
    assert_response :success
    get new_support_request_path(step: 'form')
    assert_response :success
  end

  test 'only webmaster reads or changes private requests, with safety first and escaped bodies' do
    inquiry = SupportRequest.create!(kind: 'inquiry', category: 'account', audience: 'member', email: 'test@example.test', body: 'ログインできません。再設定も試しました。')
    safety = SupportRequest.create!(kind: 'safety', category: 'review', audience: 'member', email: 'test@example.test', body: '<script>alert(1)</script>安全に関する報告です。')
    [super_admin_support_requests_path, super_admin_support_request_path(inquiry)].each do |path|
      get path
      assert_redirected_to new_webmaster_session_path
    end
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    patch super_admin_support_request_path(inquiry), params: { support_request: { status: 'resolved' } }
    assert_equal 'pending', inquiry.reload.status
    login_master
    get super_admin_support_requests_path
    assert_response :success
    links = css_select('.wm-actions a').map { |link| link['href'] }.select { |href| href.match?(%r{/support_requests/\d+}) }
    assert_equal [super_admin_support_request_path(safety), super_admin_support_request_path(inquiry)], links
    get super_admin_support_request_path(safety)
    assert_response :success
    assert_select '.wm-body script', count: 0
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_not_includes response.body, 'googletagmanager'
    assert_no_difference('ActionMailer::Base.deliveries.size') do
      patch super_admin_support_request_path(inquiry), params: { support_request: { status: 'resolved', staff_note: '対応済みです', email: 'changed@example.test' } }
    end
    assert_equal 'resolved', inquiry.reload.status
    assert_equal '対応済みです', inquiry.staff_note
    assert_equal 'test@example.test', inquiry.email
  end

  test 'suggestions go to opinion box and search failures and answer feedback reach monthly summary' do
    suggestion = SupportRequest.create!(kind: 'suggestion', category: 'other', audience: 'member', email: 'test@example.test', body: 'ヘルプの機能を増やしてほしいです。')
    HelpEvent.create!(kind: 'search', query: '検索ゼロの言葉', result_count: 0, visitor_key: 'v', recorded_on: Date.current)
    HelpEvent.create!(kind: 'unhelpful', article_id: 'login', visitor_key: 'v', recorded_on: Date.current)
    login_master
    get super_admin_opinions_path
    assert_includes response.body, suggestion.body
    get super_admin_support_requests_path
    assert_includes response.body, '検索ゼロの言葉'
    assert_includes response.body, '0.0%'
    assert_includes response.body, '改善提案：1件'
    assert_select "a[href='#{super_admin_support_request_path(suggestion)}']", count: 0
    get webmaster_path
    assert_select "a[href='#{super_admin_support_requests_path}']"
  end

  test 'legacy opinion endpoint checks ownership and sends no immediate mail' do
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    assert_difference('Opinion.count', 1) do
      assert_no_difference('ActionMailer::Base.deliveries.size') { post user_opinions_path(@circle), params: { opinion: { opinion: '運営への改善提案です。' } } }
    end
    another = AdminUser.create!(email: 'another@example.test', password: 'test-password-123')
    copy = @circle.dup
    copy.admin_user = another
    copy.save!
    delete destroy_admin_user_session_path
    post admin_user_session_path, params: { admin_user: { email: another.email, password: 'test-password-123' } }
    assert_no_difference('Opinion.count') { post user_opinions_path(@circle), params: { opinion: { opinion: 'なりすまし投稿です。' } } }
    assert_not_equal 200, response.status
  end

  test 'suggestions allow no email and cannot assign another user or bypass request limits' do
    get new_support_request_path(kind: 'suggestion', category: 'other', step: 'form')
    assert_select 'input[type=email][required]', count: 0
    token = css_select('form[action="/support"] input[name=spam_form_token]').first['value']
    payload = request_params(token)
    payload[:support_request].merge!(kind: 'suggestion', category: 'other', email: '', member_id: @member.id, status: 'resolved')
    post support_requests_path, params: payload
    assert_response :see_other
    assert_equal '', SupportRequest.last.email
    assert_nil SupportRequest.last.member_id
    assert_equal 'pending', SupportRequest.last.status
    4.times { post support_requests_path, params: request_params(token) }
    assert_no_difference('SupportRequest.count') { post support_requests_path, params: request_params(token) }
    assert_response :too_many_requests
  end

  test 'signed in submitters are recorded from session and linked in webmaster lists and details' do
    post member_session_path, params: { member: { email: @member.email, password: 'test-password-123' } }
    get new_support_request_path(step: 'form')
    token = css_select('form[action="/support"] input[name=spam_form_token]').first['value']
    payload = request_params(token)
    payload[:support_request].merge!(member_id: @other_member.id, admin_user_id: @owner.id)
    post support_requests_path, params: payload
    inquiry = SupportRequest.last
    assert_equal @member.id, inquiry.member_id
    assert_nil inquiry.admin_user_id
    delete destroy_member_session_path

    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    get new_support_request_path(kind: 'suggestion', step: 'form')
    token = css_select('form[action="/support"] input[name=spam_form_token]').first['value']
    payload = request_params(token)
    payload[:support_request].merge!(kind: 'suggestion', email: '', member_id: @member.id)
    post support_requests_path, params: payload
    suggestion = SupportRequest.last
    assert_equal @owner.id, suggestion.admin_user_id
    assert_nil suggestion.member_id
    delete destroy_admin_user_session_path

    login_master
    get super_admin_support_requests_path
    assert_select ".wm-submission-author a[href='#{super_admin_account_path(@member, kind: 'member')}']", text: /参加者さくら/
    get super_admin_support_request_path(inquiry)
    assert_select ".wm-submission-author a[href='#{super_admin_account_path(@member, kind: 'member')}']"
    get super_admin_account_path(@member, kind: 'member')
    assert_response :success
    get super_admin_opinions_path
    assert_select ".wm-submission-author a[href='#{super_admin_account_path(@owner, kind: 'owner')}']", text: /ID：#{@owner.id}/
    get super_admin_support_request_path(suggestion)
    assert_select ".wm-submission-author a[href='#{super_admin_account_path(@owner, kind: 'owner')}']"
    get super_admin_account_path(@owner, kind: 'owner')
    assert_response :success
  end

  test 'anonymous identity is not inferred from email and removed accounts have no broken links' do
    anonymous = SupportRequest.create!(kind: 'inquiry', category: 'account', audience: 'member', email: @member.email, body: 'ログインできない状況を確認してください。')
    removed = SupportRequest.create!(kind: 'suggestion', category: 'other', audience: 'member', member: @other_member, body: '今後の機能について改善をお願いします。')
    @other_member.destroy!
    login_master
    get super_admin_support_request_path(anonymous)
    assert_select '.wm-submission-author', text: /未ログイン・投稿者情報なし/
    assert_select '.wm-submission-author a', count: 0
    get super_admin_support_request_path(removed)
    assert_select '.wm-submission-author', text: /削除済み・確認不可/
    assert_select '.wm-submission-author a', count: 0
  end

  private

  def request_params(token)
    { spam_form_token: token, support_request: { kind: 'inquiry', category: 'account', audience: 'other', email: 'test@example.test', body: 'ログインできません。再設定も試しました。' } }
  end

  def login_master
    post webmaster_session_path, params: { webmaster: { email: @master.email, password: 'test-password-123' } }
  end
end
