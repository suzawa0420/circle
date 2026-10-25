require 'test_helper'

class PlaceImportCandidatesTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    run = PlaceImportRun.create!(source: 'setagaya_sports', mode: 'preview', status: 'completed', summary: { 'pending' => 1 })
    @candidate = PlaceImportCandidate.create!(source: run.source, source_url: 'https://www.se-sports.or.jp/facility/example/',
      fingerprint: 'admin-test', checked_at: Time.current, place_import_run: run,
      payload: { 'name' => '<script>alert(1)</script>候補体育館', 'address' => '東京都世田谷区尾山台3-19-3', 'sports' => ['バスケットボール'],
        'evidence' => [{ 'url' => 'https://www.se-sports.or.jp/facilityinfo/example/', 'label' => '体育館', 'text' => 'バスケットボール 1面' }], 'alerts' => [] })
    @master = Webmaster.create!(id: 1, email: 'import-master@example.test', password: 'test-password-123')
  end

  test 'only webmaster can view or dismiss candidates' do
    get super_admin_place_import_candidates_path
    assert_redirected_to new_webmaster_session_path
    get super_admin_place_import_candidate_path(@candidate)
    assert_redirected_to new_webmaster_session_path
    patch super_admin_place_import_candidate_path(@candidate), params: { decision: 'dismiss' }
    assert_redirected_to new_webmaster_session_path
    assert_equal 'pending', @candidate.reload.status
    post webmaster_session_path, params: { webmaster: { email: @master.email, password: 'test-password-123' } }
    get super_admin_place_import_candidates_path
    assert_response :success
    assert_select 'a', text: '<script>alert(1)</script>候補体育館'
    get super_admin_place_import_candidate_path(@candidate)
    assert_response :success
    assert_not_includes response.body, '<script>alert(1)</script>'
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_includes response.headers['X-Robots-Tag'], 'noindex'
    assert_no_difference('Place.count') do
      patch super_admin_place_import_candidate_path(@candidate), params: { decision: 'register', status: 'registered', payload: { 'name' => '改ざん' } }
    end
    assert_equal 'pending', @candidate.reload.status
    patch super_admin_place_import_candidate_path(@candidate), params: { decision: 'dismiss' }
    assert_equal 'dismissed', @candidate.reload.status
  end
end
