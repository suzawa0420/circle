require 'test_helper'
require_relative '../support/chat_records'

class WebmasterNavigationTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    @master = Webmaster.create!(id: 1, email: 'webmaster@example.test', password: 'test-password-123')
  end

  test 'navigation counts pending work and refreshes after resolution' do
    inquiry = SupportRequest.create!(kind: 'inquiry', category: 'account', audience: 'other', email: 'test@example.test', body: 'ログインできないので確認してください。')
    SupportRequest.create!(kind: 'safety', category: 'review', audience: 'other', email: 'test@example.test', body: '安全に関する問題を報告します。')
    SupportRequest.create!(kind: 'suggestion', category: 'other', audience: 'other', body: '活動日の機能を改善してほしいです。')
    SupportRequest.create!(kind: 'inquiry', category: 'account', audience: 'other', email: 'test@example.test', body: '対応が終わった問い合わせです。', status: 'resolved')
    report = ChatReport.create!(conversation: @conversation, reporter_role: 'member', reason: '迷惑な勧誘がありました。')
    ChatReport.create!(conversation: @conversation, reporter_role: 'member', reason: '確認中の報告になります。', status: 'in_progress')
    message = @conversation.chat_messages.where(sender_role: 'member').first!
    message.update_columns(moderation_status: 'held')
    @circle.update_columns(moderation_status: 'review')
    login_master
    get webmaster_path
    assert_response :success
    assert_badge super_admin_support_requests_path, '2'
    assert_badge super_admin_opinions_path, '1'
    assert_badge super_admin_chat_reports_path, '1'
    assert_badge super_admin_chat_moderations_path, '1'
    assert_badge super_admin_circles_path(anchor: 'pending-posts'), '1'
    inquiry.update!(status: 'resolved')
    report.update!(status: 'resolved')
    message.update_columns(moderation_status: 'approved')
    @circle.update_columns(moderation_status: 'clear')
    get super_admin_opinions_path
    assert_badge super_admin_support_requests_path, '1'
    [super_admin_chat_reports_path, super_admin_chat_moderations_path, super_admin_circles_path(anchor: 'pending-posts')].each do |path|
      assert_select ".webmaster-subnav a[href='#{path}'] .webmaster-subnav__count", count: 0
    end
  end

  test 'incoming work comes first and empty counts are hidden' do
    login_master
    get webmaster_path
    paths = css_select('.webmaster-subnav a').map { |a| a['href'] }
    assert_equal [super_admin_support_requests_path, super_admin_chat_reports_path, super_admin_chat_moderations_path, super_admin_opinions_path], paths.first(4)
    assert_equal [super_admin_circles_path, super_admin_accounts_path], paths.last(2)
    assert_select '.webmaster-subnav__count', count: 0
  end

  test 'large counts stay compact while accessible label retains full count' do
    100.times { SupportRequest.create!(kind: 'suggestion', category: 'other', audience: 'other', body: '活動日の機能を改善してほしいです。') }
    login_master
    get webmaster_path
    assert_badge super_admin_opinions_path, '99+'
    assert_select ".webmaster-subnav a[href='#{super_admin_opinions_path}'][aria-label='ご意見箱：未対応・確認待ち100件']"
  end

  test 'management page no longer exposes sport classification review' do
    @circle.update!(name: 'ピックルボールの体験会')
    login_master
    get super_admin_circles_path, params: { sport_review: 'pickleball' }
    assert_response :success
    assert_select 'h2', text: '種目の分類確認', count: 0
    assert_select 'nav[aria-label="種目の分類候補"]', count: 0
    assert_select '#pending-posts', count: 1
  end

  test 'reports are newest first regardless of resolution with stable ordering and status filtering' do
    login_master
    older = ChatReport.create!(conversation: @conversation, reporter_role: 'member', reason: '古い未対応の通報です。', created_at: 2.days.ago)
    newer = ChatReport.create!(conversation: @conversation, reporter_role: 'member', reason: '新しい対応済みの通報です。', status: 'resolved', created_at: 1.day.ago)
    same_time = ChatReport.create!(conversation: @conversation, reporter_role: 'member', reason: '同時刻の未対応の通報です。', created_at: newer.created_at)
    get super_admin_chat_reports_path
    assert_response :success
    assert_equal [same_time, newer, older].map { |report| super_admin_chat_report_path(report) }, css_select('.wm-list .wm-actions a').map { |link| link['href'] }
    get super_admin_chat_reports_path, params: { status: 'pending' }
    assert_equal [same_time, older].map { |report| super_admin_chat_report_path(report) }, css_select('.wm-list .wm-actions a').map { |link| link['href'] }
    assert_select '.wm-report-filter__controls select[name="status"] option[selected]', text: '未対応'
  end

  private

  def login_master
    post webmaster_session_path, params: { webmaster: { email: @master.email, password: 'test-password-123' } }
  end

  def assert_badge(path, text)
    assert_select ".webmaster-subnav a[href='#{path}'] .webmaster-subnav__count", count: 1, text: text
  end
end
