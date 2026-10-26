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

  test 'webmaster can correct imported access and parking without losing line breaks' do
    category = Category.create!(name: '球技', kana: 'import-edit-ball', order: '1')
    event = Event.create!(name: 'バスケ', ruby: 'import-edit-basketball', category: category, place: 1, order: '1')
    prefecture = Prefecture.create!(name: '大阪府', kana: 'import-edit-osaka', order: '1')
    city = City.create!(name: '吹田市', city_kana: 'suita', prefecture: prefecture)
    place = Place.create!(name: '修正用体育館', prefecture: prefecture, city: city, address: '大阪府吹田市1-2', tag: '1', events: [event])
    post webmaster_session_path, params: { webmaster: { email: @master.email, password: 'test-password-123' } }
    get edit_place_path(place)
    assert_response :success
    %w[access parking regular_holiday].each { |key| assert_select "textarea[name='place[#{key}]']" }
    corrections = { access: "阪急線：駅から徒歩8分\nJR線：駅から徒歩15分",
      parking: "32台・専用ではありません\n30分無料、以降100円", regular_holiday: "第2月曜日\n年末年始" }
    patch place_path(place), params: { place: corrections }
    assert_response :redirect
    place.reload
    corrections.each { |key, value| assert_equal value, place.public_send(key) }
  end
end
