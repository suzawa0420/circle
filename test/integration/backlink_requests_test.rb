require 'test_helper'
require_relative '../support/chat_records'

class BacklinkRequestsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords
  include ActiveJob::TestHelper

  setup do
    create_chat_records
    @circle.update!(user_time: Time.current.to_s)
    @master = Webmaster.create!(id: 1, email: 'backlink-master@example.test', password: 'test-password-123')
  end

  test 'owner page includes circle link, both snippets, logo download and private response' do
    host! 'www.example.com:3149'
    login_owner
    get circle_backlink_request_path(@circle)
    assert_response :success
    assert_select '#backlink-url[value=?]', "https://circle-book.com/circles/#{@circle.id}"
    assert_select 'textarea#backlink-banner', text: /<img/
    assert_select 'textarea#backlink-text', text: /サークルブック/
    assert_select 'a[download="circlebook-logo.png"]'
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_not_includes response.body, 'googletagmanager'
  end

  test 'submission notifies only once and does not award points before review' do
    login_owner
    assert_enqueued_emails 1 do
      assert_difference 'BacklinkRequest.count', 1 do
        submit
      end
    end
    request = BacklinkRequest.last
    assert_equal 'pending', request.status
    assert_equal 0, @circle.reload.cb_point
    assert_no_enqueued_emails do
      assert_no_difference 'BacklinkRequest.count' do
        submit
      end
    end
    mail = BacklinkRequestMailer.submitted(request)
    assert_equal ['circlebook26@gmail.com'], mail.to
    assert_includes mail.body.encoded, 'https://circle-book.com/super_admin/backlink_requests/'
  end

  test 'approval survives score refresh, duplicate decisions cannot award twice, and revocation removes only bonus' do
    @circle.schedules.create!(title: '活動', venue: '体育館', day: (Date.current + 7).to_s)
    request = BacklinkRequest.submit!(@circle, 'https://example.test/circle')
    login_master
    get super_admin_backlink_requests_path
    assert_response :success
    assert_select '.wm-backlink-statuses a[aria-current=page]', text: /確認中.*1/m
    assert_select '.wm-list .webmaster-card .wm-button', text: '申請を確認する'
    assert_select ".webmaster-subnav a[href='#{super_admin_backlink_requests_path}'] .webmaster-subnav__count", text: '1'
    get super_admin_backlink_request_path(request)
    assert_response :success
    assert_select '.webmaster-card .backlink-placement[href=?]', request.placement_url
    assert_select '.wm-backlink-checklist li', count: 2
    assert_select '.wm-field textarea[name=review_note][aria-describedby=backlink-review-hint]'
    patch super_admin_backlink_request_path(request), params: { decision: 'approve' }
    assert_equal 'approved', request.reload.status
    assert_in_delta 10.1, @circle.reload.cb_point
    patch super_admin_backlink_request_path(request), params: { decision: 'approve' }
    assert_in_delta 10.1, @circle.reload.cb_point
    CircleScoreUpdater.new.refresh(@circle)
    assert_in_delta 10.1, @circle.cb_point
    patch super_admin_backlink_request_path(request), params: { decision: 'revoke', review_note: 'リンクが削除されています。' }
    assert_equal 'revoked', request.reload.status
    assert_equal @master.id, request.reviewed_by_id
    assert request.approved_at
    assert request.revoked_at
    assert_in_delta 0.1, @circle.reload.cb_point
    patch super_admin_backlink_request_path(request), params: { decision: 'approve' }
    assert_in_delta 0.1, @circle.reload.cb_point
    assert_equal 'revoked', BacklinkRequest.submit!(@circle, 'https://example.test/new').status
  end

  test 'rejection requires reason and permits corrected resubmission' do
    request = BacklinkRequest.submit!(@circle, 'https://example.test/old')
    login_master
    patch super_admin_backlink_request_path(request), params: { decision: 'reject' }
    assert_response :unprocessable_entity
    assert_equal 'pending', request.reload.status
    assert_select 'button[value="approve"]'
    patch super_admin_backlink_request_path(request), params: { decision: 'reject', review_note: 'リンク先をご確認ください。' }
    assert_equal 'rejected', request.reload.status
    delete destroy_webmaster_session_path
    login_owner
    get circle_backlink_request_path(@circle)
    assert_includes response.body, 'リンク先をご確認ください。'
    post circle_backlink_request_path(@circle), params: { backlink_request: { placement_url: 'javascript:alert(1)' } }
    assert_response :unprocessable_entity
    assert_select 'input[type="url"]'
    assert_enqueued_emails 1 do
      post circle_backlink_request_path(@circle), params: { backlink_request: { placement_url: 'https://example.test/fixed' } }
    end
    assert_equal 'pending', request.reload.status
    assert_equal 'https://example.test/fixed', request.placement_url
  end

  test 'empty status lists keep the selected filter and use the shared empty state' do
    login_master
    get super_admin_backlink_requests_path(status: 'approved')
    assert_response :success
    assert_select '.wm-backlink-statuses a', count: 4
    assert_select '.wm-backlink-statuses a[aria-current=page]', text: /付与済み.*0/m
    assert_select '.wm-empty', text: '付与済みの申請はありません。'
  end

  test 'authentication and ownership are required and owners cannot review' do
    get circle_backlink_request_path(@circle)
    assert_redirected_to new_admin_user_session_path
    other = AdminUser.create!(email: 'other-backlink@example.test', password: 'test-password-123', email_verified_at: Time.current)
    second = @circle.dup
    second.assign_attributes(admin_user: other, name: '別のサークル')
    second.save!
    login_owner
    get circle_backlink_request_path(second)
    assert_response :forbidden
    assert_no_difference 'BacklinkRequest.count' do
      post circle_backlink_request_path(second), params: { backlink_request: { placement_url: 'https://example.test/' } }
    end
    assert_response :forbidden
    request = BacklinkRequest.submit!(@circle, 'https://example.test/')
    patch super_admin_backlink_request_path(request), params: { decision: 'approve' }
    assert_redirected_to new_webmaster_session_path
    assert_equal 'pending', request.reload.status
  end

  test 'unsafe URLs and injected status are rejected or ignored' do
    login_owner
    ['javascript:alert(1)', '//example.test/', 'https://user:pass@example.test/', 'not a url'].each do |url|
      assert_no_difference 'BacklinkRequest.count' do
        post circle_backlink_request_path(@circle), params: { backlink_request: { placement_url: url } }
      end
      assert_response :unprocessable_entity
    end
    post circle_backlink_request_path(@circle), params: { backlink_request: { placement_url: 'https://example.test/', status: 'approved', user_id: 999 } }
    assert_equal 'pending', BacklinkRequest.last.status
    assert_equal @circle.id, BacklinkRequest.last.user_id
  end

  test 'different circles can apply independently and inactive or restricted circles retain scoring rules' do
    second = @circle.dup
    second.save!
    first_request = BacklinkRequest.submit!(@circle, 'https://example.test/')
    second_request = BacklinkRequest.submit!(second, 'https://example.test/second')
    assert_not_equal first_request.id, second_request.id
    @circle.update!(user_time: 2.years.ago.to_s)
    first_request.review!('approve', @master, '')
    assert_equal 0, @circle.reload.cb_point
    @circle.update!(user_time: Time.current.to_s)
    CircleScoreUpdater.new.refresh(@circle)
    assert_equal 10, @circle.cb_point
    @owner.update!(check: 1)
    CircleScoreUpdater.new.refresh(@circle.reload)
    assert_equal(-100, @circle.cb_point)
  end

  private

  def submit
    post circle_backlink_request_path(@circle), params: { backlink_request: { placement_url: 'https://example.test/circle' } }
  end

  def login_owner
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
  end

  def login_master
    post webmaster_session_path, params: { webmaster: { email: @master.email, password: 'test-password-123' } }
  end
end
