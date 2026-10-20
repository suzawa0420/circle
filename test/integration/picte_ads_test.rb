require 'test_helper'
require_relative '../support/chat_records'

class PicteAdsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    @camera = Event.create!(name: '写真・カメラ', ruby: 'camera', category: @circle.category, order: '2')
  end

  test 'only camera search pages show the ad with the search UTM' do
    get event_path(@circle.event.ruby)
    assert_select '.picte-ad', count: 0
    @circle.update!(event: @camera)
    get event_path('camera')
    assert_response :success
    assert_select '.picte-ad', count: 1
    assert_ad 'search', 'camera_search_v1'
    get event_prefecture_path('camera', @circle.prefecture.kana)
    assert_response :success
    assert_ad 'search', 'camera_search_v1'
    get circles_search_index_path, params: { detailed: '1', event_id: @camera.id, q: 'サークル' }
    assert_response :success
    assert_ad 'search', 'camera_search_v1'
    get circles_path
    assert_select '.picte-ad', count: 0
  end

  test 'camera ad occurs once after the second circle and on empty camera searches' do
    @circle.update!(event: @camera)
    4.times do |i|
      copy = @circle.dup
      copy.assign_attributes(name: "写真部#{i}", unique_id: nil)
      copy.save!
    end
    get event_path('camera')
    assert_select '.circle-results-grid > .user_item_wrap', count: 5
    assert_select '.circle-results-grid > li:nth-child(3).picte-ad-slot', count: 1
    assert_select '.picte-ad', count: 1
    get circles_search_index_path, params: { detailed: '1', event_id: @camera.id, q: '見つからない写真部' }
    assert_response :success
    assert_select '.picte-ad', count: 1
  end

  test 'owner sees organizer copy only while managing a camera circle' do
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    get "/users/#{@circle.id}/mypage"
    assert_select '.picte-ad', count: 0
    @circle.update!(event: @camera)
    get "/users/#{@circle.id}/mypage"
    assert_response :success
    assert_select '.picte-ad', count: 1
    assert_ad 'mypage', 'organizer_mypage_v1'
    assert_select '.picte-ad__title', text: '撮影の次は、みんなで写真展へ。'
    assert_select '.dashboard-section + .picte-ad', count: 1
  end

  test 'clicks accumulate per placement and Japanese date without individual records' do
    travel_to Time.utc(2026, 10, 20, 15, 5) do
      2.times { post picte_ad_clicks_path, params: { placement: 'search' }; assert_response :no_content }
      post picte_ad_clicks_path, params: { placement: 'mypage' }
      assert_response :no_content
      assert_equal({ 'search' => 2, 'mypage' => 1 }, PicteAdClickCount.where(recorded_on: Date.new(2026, 10, 21)).pluck(:placement, :click_count).to_h)
      assert_equal 2, PicteAdClickCount.count
      assert_equal %w[id recorded_on placement click_count], PicteAdClickCount.column_names
    end
    assert_no_difference('PicteAdClickCount.sum(:click_count)') do
      post picte_ad_clicks_path, params: { placement: 'unknown' }
      assert_response :unprocessable_entity
      get event_path('camera')
      assert_response :success
    end
  end

  test 'click endpoint rejects cross site submissions' do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    assert_raises(ActionController::InvalidAuthenticityToken) do
      post picte_ad_clicks_path, params: { placement: 'search' }, headers: { 'Origin' => 'https://unrelated.example' }
    end
    assert_equal 0, PicteAdClickCount.count
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  test 'only webmasters can view totals and daily counts' do
    PicteAdClickCount.record_click!('search')
    get super_admin_picte_ad_clicks_path
    assert_redirected_to new_webmaster_session_path
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    get super_admin_picte_ad_clicks_path
    assert_redirected_to new_webmaster_session_path
    master = Webmaster.create!(id: 1, email: 'picte-webmaster@example.test', password: 'test-password-123')
    post webmaster_session_path, params: { webmaster: { email: master.email, password: 'test-password-123' } }
    get super_admin_picte_ad_clicks_path
    assert_response :success
    assert_select 'h1', text: 'PICTE広告のクリック数'
    assert_select 'tbody tr', count: 30
    assert_select '.wm-support-metrics dd strong', text: '1'
    assert_includes response.headers['Cache-Control'], 'no-store'
  end

  private

  def assert_ad(placement, content)
    assert_select "a[data-picte-ad-click='#{placement}'][data-picte-click-url='/picte-ad-clicks']", count: 1 do |links|
      url = URI.parse(links.first['href'])
      assert_equal 'picte-photo.com', url.host
      assert_equal '/service/share-exhibition/', url.path
      assert_equal({ 'utm_source' => 'circlebook', 'utm_medium' => 'display', 'utm_campaign' => 'picte_share_exhibition', 'utm_content' => content }, Rack::Utils.parse_query(url.query))
      assert_includes links.first['rel'], 'sponsored'
    end
    assert_select '.picte-ad img[width="1280"][height="853"][loading="lazy"]'
  end
end
