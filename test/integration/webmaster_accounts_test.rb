require 'test_helper'
require_relative '../support/chat_records'

class WebmasterAccountsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords
  setup do
    create_chat_records
    @master = Webmaster.create!(id: 1, email: 'webmaster@example.test', password: 'test-password-123')
  end

  test 'account management is private and searchable with related history' do
    get super_admin_accounts_path
    assert_redirected_to new_webmaster_session_path
    post member_session_path, params: { member: { email: @member.email, password: 'test-password-123' } }
    patch super_admin_account_path(@member), params: { operation: 'suspend' }
    assert_redirected_to new_webmaster_session_path
    assert_not @member.reload.suspended?
    login_master
    get super_admin_accounts_path, params: { q: @member.nickname }
    assert_response :success
    assert_includes response.body, @member.nickname
    assert_not_includes response.body, @other_member.email
    get super_admin_account_path(@member)
    assert_response :success
    assert_includes response.body, super_admin_conversation_path(@conversation)
    assert_includes response.headers['Cache-Control'], 'no-store'
    get super_admin_account_path(@owner, kind: 'owner')
    assert_response :success
  end

  test 'confirmation required and suspension can be reversed' do
    login_master
    patch super_admin_account_path(@member), params: { operation: 'suspend', reason: '不適切な投稿' }
    assert_not @member.reload.suspended?
    get confirm_super_admin_account_path(@member, operation: 'suspend')
    assert_response :success
    token = css_select('input[name="confirmation"]').first['value']
    patch super_admin_account_path(@other_member), params: { operation: 'suspend', reason: '不適切な投稿', confirmation: token }
    assert_not @other_member.reload.suspended?
    patch super_admin_account_path(@member), params: { operation: 'suspend', reason: '不適切な投稿', confirmation: token }
    assert @member.reload.suspended?
    get super_admin_accounts_path, params: { state: 'suspended' }
    assert_includes response.body, @member.email
    assert_not_includes response.body, @other_member.email
    get confirm_super_admin_account_path(@member, operation: 'resume')
    token = css_select('input[name="confirmation"]').first['value']
    patch super_admin_account_path(@member), params: { operation: 'resume', confirmation: token }
    assert_not @member.reload.suspended?
  end

  test 'suspension blocks writes even with stale model and preserves history and reports' do
    accept_conversation
    @conversation.member # cached before suspension
    @member.update!(suspended_at: Time.current)
    assert_raises(Conversation::NotAllowed) { @conversation.send_message!('member', '送信できません') }
    assert_raises(Conversation::NotAllowed) { @conversation.submit_review!('member', member_evaluation) }
    assert_raises(Conversation::NotAllowed) { Conversation.for_member!(@circle, @member) }
    post member_session_path, params: { member: { email: @member.email, password: 'test-password-123' } }
    get conversation_path(@conversation)
    assert_response :success
    assert_includes response.body, 'はじめまして。参加できますか？'
    assert_select 'form.chat-compose-form', count: 0
    assert_no_difference('ChatMessage.count') { post message_conversation_path(@conversation), params: { message: { body: '送信できません' } } }
    assert_no_difference('ConversationReview.count') { put review_conversation_path(@conversation), params: { evaluation: member_evaluation } }
    @owner.update!(suspended_at: Time.current)
    assert_raises(Conversation::NotAllowed) { @conversation.send_message!('owner', '送信できません') }
    assert_raises(Conversation::NotAllowed) { @conversation.submit_review!('owner', owner_evaluation) }
    assert_raises(Conversation::NotAllowed) { Conversation.for_member!(@circle, @other_member) }
    @member.update!(suspended_at: nil)
    @conversation.send_message!('member', '利用再開後は送信できます')
  end

  test 'report status memo and reopening remain private' do
    report = ChatReport.create!(conversation: @conversation, reporter_role: 'member', reason: '不適切な内容の報告です')
    login_master
    patch super_admin_chat_report_path(report), params: { chat_report: { status: 'in_progress', operational_memo: '運営専用メモです' } }
    assert_equal 'in_progress', report.reload.status
    assert_nil report.resolved_at
    patch super_admin_chat_report_path(report), params: { chat_report: { status: 'resolved' } }
    assert report.reload.resolved_at
    patch super_admin_chat_report_path(report), params: { chat_report: { status: 'pending' } }
    assert_nil report.reload.resolved_at
    patch super_admin_chat_report_path(report), params: { chat_report: { status: 'invalid' } }
    assert_response :unprocessable_entity
    assert_equal 'pending', report.reload.status
    get super_admin_chat_reports_path, params: { status: 'in_progress' }
    assert_not_includes response.body, report.reason
    get super_admin_account_path(@member)
    assert_includes response.body, report.reason
    delete destroy_webmaster_session_path
    post member_session_path, params: { member: { email: @member.email, password: 'test-password-123' } }
    get conversation_path(@conversation)
    assert_not_includes response.body, '運営専用メモです'
  end

  test 'suspended member legacy review remains deletable by webmaster' do
    review = @circle.reviews.create!(member: @other_member, review: 1, comment: '参加した時の口コミです。')
    @other_member.update!(suspended_at: Time.current)
    login_master
    delete user_review_path(@circle, review)
    assert_not Review.exists?(review.id)
    assert Conversation.find_by!(user: @circle, member: @other_member).legacy_member_review?
  end

  test 'legacy owner delete goes through impact confirmation' do
    login_master
    assert_no_difference('AdminUser.count') { delete super_admin_circle_path(@owner) }
    assert_redirected_to confirm_super_admin_account_path(@owner, kind: 'owner', operation: 'delete')
    follow_redirect!
    assert_response :success
    assert_includes response.body, 'この操作は取り消せません'
    token = css_select('input[name="confirmation"]').first['value']
    assert_difference('AdminUser.count', -1) do
      patch super_admin_account_path(@owner, kind: 'owner'), params: { operation: 'delete', confirmation: token }
    end
    assert_not User.exists?(@circle.id)
    assert_not Conversation.exists?(@conversation.id)
  end

  private
  def login_master
    post webmaster_session_path, params: { webmaster: { email: @master.email, password: 'test-password-123' } }
  end
end
