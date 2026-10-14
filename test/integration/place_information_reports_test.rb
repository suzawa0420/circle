require 'test_helper'

class PlaceInformationReportsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    category = Category.create!(name: '球技', kana: 'report-ball', order: '1')
    @event = Event.create!(name: 'バスケ', ruby: 'report-basketball', category: category, place: 1, order: '1')
    prefecture = Prefecture.create!(name: '東京都', kana: 'report-tokyo', order: '1')
    city = City.create!(name: '目黒区', city_kana: 'meguro', prefecture_id: prefecture.id)
    @place = Place.create!(name: '修正依頼体育館', prefecture: prefecture, city: city, events: [@event], tag: '1', address: '東京都目黒区1-2-3')
    @master = Webmaster.create!(id: 1, email: 'report-master@example.test', password: 'test-password-123')
  end

  test 'anonymous report form follows reviews and accepts Japanese reports into private inbox without mail or facility changes' do
    get facility_path
    assert_response :success
    assert_select '#place-information-report form[action=?]', place_information_reports_path(@place)
    assert_operator response.body.index('place-information-report'), :>, response.body.index('place-review-form-title')
    token = form_token
    assert_difference('PlaceInformationReport.count') do
      assert_no_difference('ActionMailer::Base.deliveries.size') do
        post place_information_reports_path(@place), params: payload(token).merge(place_information_report: payload(token)[:place_information_report].merge(status: 'resolved', staff_note: '改ざんメモ', place_id: 0, place_name: '改ざん施設'))
      end
    end
    assert_response :see_other
    report = PlaceInformationReport.last
    assert_equal @place.id, report.place_id
    assert_equal @place.name, report.place_name
    assert_equal 'pending', report.status
    assert_nil report.staff_note
    assert_nil report.reviewed_by
    assert_equal '修正依頼体育館', @place.reload.name
    follow_redirect!
    assert_response :success
    assert_includes response.body, '修正依頼を受け付けました'
    assert_not_includes response.body, report.body
    assert_includes response.headers['Cache-Control'], 'no-store'
  end

  test 'both kanji and hiragana are required and invalid reports preserve entered content' do
    ['The facility is closed.', '施設閉鎖情報確認依頼', 'たいいくかんがしまっています。', '体育館です'].each do |body|
      get new_place_information_report_path(@place)
      data = payload(form_token)
      data[:place_information_report][:body] = body
      assert_no_difference('PlaceInformationReport.count') { post place_information_reports_path(@place), params: data }
      assert_response :unprocessable_entity
      assert_select 'textarea', text: body
      assert_includes response.headers['X-Robots-Tag'], 'noindex'
    end
    assert_select '[role=alert]'
    assert_not_includes response.body, 'googletagmanager'
    assert_not_includes response.body, 'pagead2.googlesyndication.com'
  end

  test 'forged scoped tokens honeypots and unsafe reference URLs are rejected' do
    get new_place_information_report_path(@place)
    token = form_token
    assert_no_difference('PlaceInformationReport.count') do
      post place_information_reports_path(@place), params: payload('forged')
      assert_response :unprocessable_entity
      post place_information_reports_path(@place), params: payload(token).merge(contact_website: 'spam')
      assert_response :unprocessable_entity
      wrong_scope = Rails.application.message_verifier(:spam_form).generate('x', purpose: 'place-information-report:999')
      post place_information_reports_path(@place), params: payload(wrong_scope)
      assert_response :unprocessable_entity
      data = payload(token)
      data[:place_information_report][:reference_url] = 'javascript:alert(1)'
      post place_information_reports_path(@place), params: data
      assert_response :unprocessable_entity
    end
  end

  test 'duplicate submissions create one report and per IP rate limits apply' do
    get new_place_information_report_path(@place)
    data = payload(form_token)
    assert_difference('PlaceInformationReport.count', 1) do
      2.times { post place_information_reports_path(@place), params: data; assert_response :see_other }
    end
    3.times do |i|
      data[:place_information_report][:body] = "利用料金が変更されています。確認をお願いします。#{i}"
      post place_information_reports_path(@place), params: data
      assert_response :see_other
    end
    assert_no_difference('PlaceInformationReport.count') { post place_information_reports_path(@place), params: data }
    assert_response :too_many_requests
    assert response.headers['Retry-After'].present?
  end

  test 'only webmaster reads reports and edits status while badge counts disappear after resolution' do
    report = create_report
    [super_admin_place_information_reports_path, super_admin_place_information_report_path(report)].each do |path|
      get path
      assert_redirected_to new_webmaster_session_path
    end
    patch super_admin_place_information_report_path(report), params: { place_information_report: { status: 'resolved' } }
    assert_redirected_to new_webmaster_session_path
    assert_equal 'pending', report.reload.status
    owner = AdminUser.create!(email: 'report-owner@example.test', password: 'test-password-123')
    post admin_user_session_path, params: { admin_user: { email: owner.email, password: 'test-password-123' } }
    get new_place_information_report_path(@place)
    assert_response :success
    get super_admin_place_information_report_path(report)
    assert_redirected_to new_webmaster_session_path
    login_master
    get webmaster_path
    assert_select ".webmaster-subnav a[href='#{super_admin_place_information_reports_path}'] .webmaster-subnav__count", text: '1'
    get super_admin_place_information_report_path(report)
    assert_response :success
    assert_select '.wm-body script', count: 0
    assert_select "a[href='#{edit_place_path(@place)}']", text: '施設情報を編集する'
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_includes response.headers['X-Robots-Tag'], 'noindex'
    assert_not_includes response.body, 'googletagmanager'
    patch super_admin_place_information_report_path(report), params: { place_information_report: { status: 'resolved', staff_note: '公式サイトを確認し、施設情報を修正しました。', body: '変更してはいけない本文', place_id: 0 } }
    assert_response :redirect
    assert_equal 'resolved', report.reload.status
    assert_equal @master.id, report.reviewed_by_id
    assert report.reviewed_at
    assert report.resolved_at
    assert_includes report.staff_note, '公式サイト'
    assert_includes report.body, '閉鎖'
    assert_equal @place.id, report.place_id
    get webmaster_path
    assert_select ".webmaster-subnav a[href='#{super_admin_place_information_reports_path}'] .webmaster-subnav__count", count: 0
    get super_admin_place_information_reports_path(status: 'resolved')
    assert_select "a[href='#{super_admin_place_information_report_path(report)}']", text: '内容を確認する'
    patch super_admin_place_information_report_path(report), params: { place_information_report: { status: 'unknown' } }
    assert_response :unprocessable_entity
    assert_equal 'resolved', report.reload.status
  end

  test 'reports remain reviewable after the facility is deleted' do
    report = create_report
    @place.destroy!
    assert_nil report.reload.place_id
    login_master
    get super_admin_place_information_report_path(report)
    assert_response :success
    assert_includes response.body, 'この施設は削除されています'
    patch super_admin_place_information_report_path(report), params: { place_information_report: { status: 'resolved', staff_note: '閉鎖を確認しました。' } }
    assert_response :redirect
    assert_equal 'resolved', report.reload.status
  end

  private

  def facility_path
    "/places/#{@event.ruby}/#{@place.prefecture.kana}/#{@place.city.city_kana}/#{@place.id}"
  end

  def form_token
    css_select('form.place-information-report-form input[name=spam_form_token]').first['value']
  end

  def payload(token)
    { spam_form_token: token, place_information_report: { kind: 'closed', body: '体育館が閉鎖されています。確認をお願いします。', reference_url: 'https://example.test/closure' } }
  end

  def create_report
    @place.place_information_reports.create!(kind: 'closed', body: '<script>alert(1)</script>体育館が閉鎖されているようです。確認をお願いします。')
  end

  def login_master
    post webmaster_session_path, params: { webmaster: { email: @master.email, password: 'test-password-123' } }
  end
end
