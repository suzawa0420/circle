require 'test_helper'
require_relative '../support/chat_records'

class NoShowReportsTest < ActionDispatch::IntegrationTest
  include ChatRecords
  self.fixture_table_names = []
  setup do
    create_chat_records
    accept_conversation
    @conversation.update!(created_at: 4.days.ago, accepted_at: 4.days.ago)
    @attributes = { scheduled_at: 1.day.ago.change(hour: 14), participation_confirmed: '1', no_advance_notice: '1',
                    confirmation_details: '事前の会話で参加すると明確に返事がありました。', details: '集合時間に来場せず、事前の連絡もありませんでした。' }
  end

  test 'owner reports from one selector and only private profiles show a count' do
    sign_in @owner
    get conversation_path(@conversation)
    assert_select '.chat-controls > summary', text: '返信なし・連絡なしの欠席'
    assert_select 'input[data-report-kind]', count: 2
    assert_difference('NoShowReport.count', 1) { post no_show_report_conversation_path(@conversation), params: { no_show_report: @attributes.merge(status: 'confirmed', member_response: '偽の本人説明') } }
    report = NoShowReport.last
    assert_equal 'pending', report.status
    assert_nil report.member_response
    get conversations_path
    assert_select '.chat-review-prompt-badge', text: '欠席の申告・本人の説明を確認'
    get member_profile_path(@member)
    assert_select '[aria-label="主催者限定の欠席申告"]', text: /1件/
    assert_equal 'private, no-store', response.headers['Cache-Control']
    assert_not_includes response.body, @attributes[:details]
    sign_out @owner
    get member_profile_path(@member)
    assert_select '[aria-label="主催者限定の欠席申告"]', count: 0
    assert_not_includes response.body, '連絡なしの欠席についての申告'
    sign_in @other_member
    get member_profile_path(@member)
    assert_select '[aria-label="主催者限定の欠席申告"], [aria-label="ご自身への欠席申告"]', count: 0
  end

  test 'only the subject can submit an explanation and operator memo stays private' do
    report = @conversation.no_show_reports.create!(@attributes.merge(operational_memo: '運営だけが見る確認メモ'))
    sign_in @member
    get conversation_path(@conversation)
    assert_select '#attendance-reports', text: /事前の会話/
    assert_select 'textarea[name="no_show_report[member_response]"]'
    assert_not_includes response.body, report.operational_memo
    patch no_show_response_conversation_path(@conversation), params: { report_id: report.id, no_show_report: { member_response: '当日は事前に欠席の連絡を送っていました。', status: 'dismissed' } }
    assert_redirected_to conversation_path(@conversation, anchor: 'attendance-reports')
    assert_equal 'pending', report.reload.status
    assert_equal '当日は事前に欠席の連絡を送っていました。', report.member_response
    assert report.member_responded_at
    get member_profile_path(@member)
    assert_select '[aria-label="ご自身への欠席申告"]'
    sign_out @member
    sign_in @owner
    patch no_show_response_conversation_path(@conversation), params: { report_id: report.id, no_show_report: { member_response: '主催者から本人の説明を上書きします。' } }
    assert_equal '当日は事前に欠席の連絡を送っていました。', report.reload.member_response
  end

  test 'unrelated accounts cannot report read details or alter another report' do
    report = @conversation.no_show_reports.create!(@attributes)
    sign_in @other_member
    assert_raises(ActiveRecord::RecordNotFound) { get conversation_path(@conversation) }
    assert_raises(ActiveRecord::RecordNotFound) { post no_show_report_conversation_path(@conversation), params: { no_show_report: @attributes } }
    sign_out @other_member
    sign_in @member
    assert_no_difference('NoShowReport.count') { post no_show_report_conversation_path(@conversation), params: { no_show_report: @attributes } }
    another = Conversation.for_member!(@circle, @other_member)
    another.send_message!('member', '別の問い合わせです。')
    another.send_message!('owner', '別の会話への返信です。')
    another.update!(created_at: 4.days.ago)
    other_report = another.no_show_reports.create!(@attributes)
    assert_raises(ActiveRecord::RecordNotFound) { patch no_show_response_conversation_path(@conversation), params: { report_id: other_report.id, no_show_report: { member_response: '他の人の報告を書き換えます。' } } }
    assert_nil other_report.reload.member_response
  end

  test 'future events unconfirmed attendance advance notice and duplicate reports are rejected' do
    sign_in @owner
    [@attributes.merge(scheduled_at: 1.day.from_now), @attributes.merge(participation_confirmed: '0'), @attributes.merge(no_advance_notice: '0'), @attributes.merge(scheduled_at: 10.days.ago)].each do |attributes|
      assert_no_difference('NoShowReport.count') { post no_show_report_conversation_path(@conversation), params: { no_show_report: attributes } }
    end
    2.times { post no_show_report_conversation_path(@conversation), params: { no_show_report: @attributes } }
    assert_equal 1, NoShowReport.count
    travel 30.days do
      assert_equal 'pending', NoShowReport.sole.status, 'silence must never automatically confirm a claim'
    end
  end

  test 'scheduled time and two confirmations are sufficient and each event counts once' do
    sign_in @owner
    get conversation_path(@conversation)
    assert_select 'textarea[name="no_show_report[confirmation_details]"], textarea[name="no_show_report[details]"]', count: 0
    simple = @attributes.slice(:scheduled_at, :participation_confirmed, :no_advance_notice)
    assert_difference('NoShowReport.count', 1) { post no_show_report_conversation_path(@conversation), params: { no_show_report: simple } }
    assert_equal '', NoShowReport.last.details
    assert_equal 1, @member.no_show_report_count
    post no_show_report_conversation_path(@conversation), params: { no_show_report: simple.merge(scheduled_at: 2.days.ago.change(hour: 14)) }
    assert_equal 2, @member.no_show_report_count
  end

  test 'other verified circle owners see only a summary and operators can dismiss a claim' do
    report = @conversation.no_show_reports.create!(@attributes)
    other_owner = AdminUser.create!(email: 'other-owner@example.test', password: 'test-password-123', email_verified_at: Time.current)
    circle = @circle.dup
    circle.admin_user = other_owner
    circle.save!
    sign_in other_owner
    get member_profile_path(@member)
    assert_select '[aria-label="主催者限定の欠席申告"]', text: /未確認の申告/
    assert_not_includes response.body, @attributes[:confirmation_details]
    get super_admin_no_show_reports_path
    assert_response :redirect
    sign_out other_owner
    master = Webmaster.create!(id: 1, email: 'webmaster@example.test', password: 'test-password-123')
    sign_in master
    get super_admin_no_show_reports_path
    assert_response :success
    get super_admin_no_show_report_path(report)
    assert_response :success
    assert_includes response.body, @attributes[:details]
    patch super_admin_no_show_report_path(report), params: { no_show_report: { status: 'dismissed', operational_memo: '双方の説明を確認し、集計対象外としました。' } }
    assert_equal 'dismissed', report.reload.status
    assert_equal 0, @member.no_show_report_count
  end

  test 'an unverified owner or an organizer without circles cannot view claims' do
    @conversation.no_show_reports.create!(@attributes)
    @owner.update_columns(email_verified_at: nil)
    sign_in @owner
    get member_profile_path(@member)
    assert_select '[aria-label="主催者限定の欠席申告"]', count: 0
    assert_no_difference('NoShowReport.count') { post no_show_report_conversation_path(@conversation), params: { no_show_report: @attributes.merge(scheduled_at: 2.days.ago) } }
    assert_not NoShowReport.profile_viewable_by?(AdminUser.new(email_verified_at: Time.current))
  end

  private

  def sign_in(account)
    if account.is_a?(Webmaster)
      post webmaster_session_path, params: { webmaster: { email: account.email, password: 'test-password-123' } }
    elsif account.is_a?(AdminUser)
      post admin_user_session_path, params: { admin_user: { email: account.email, password: 'test-password-123' } }
    else
      post member_session_path, params: { member: { email: account.email, password: 'test-password-123' } }
    end
  end

  def sign_out(account)
    delete(account.is_a?(AdminUser) ? destroy_admin_user_session_path : destroy_member_session_path)
  end
end
