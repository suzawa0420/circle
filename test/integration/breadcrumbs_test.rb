require 'test_helper'
require_relative '../support/chat_records'

class BreadcrumbsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup { create_chat_records }

  test 'unconfigured public pages and account forms have a labelled current page' do
    {
      '/' => 'ホーム', '/about' => 'サークルブックについて', '/rules' => '利用規約',
      '/privacypolicy' => 'プライバシーポリシー', '/faq' => 'ヘルプセンター・よくある質問',
      '/support/new' => '運営への連絡', '/support/thanks' => '受付完了',
      '/members/sign_in' => '参加者のログイン', '/members/sign_up' => '参加者の新規登録',
      '/members/password/new' => '参加者のパスワード再設定',
      '/admin_users/sign_in' => '主催者のログイン', '/admin_users/sign_up' => '主催者の新規登録'
    }.each do |path, label|
      get path
      assert_response :success, path
      assert_trail(label)
    end
  end

  test 'existing circle hierarchy remains linked and current page is escaped' do
    @circle.update!(name: '長い名称 <script>alert(1)</script> のサークル')
    get circle_path(@circle)
    assert_response :success
    assert_trail(@circle.name)
    assert_select '.breadcrumbs a[href="/circles"]', text: 'サークル一覧'
    assert_select '.breadcrumbs script', count: 0
    assert_select '.breadcrumbs a', text: @circle.name, count: 0
  end

  test 'blog detail uses the current nested blog route' do
    blog = @circle.blogs.create!(title: '活動報告', content: '楽しく活動しました。' * 20)
    get circle_blog_path(@circle, blog)
    assert_response :success
    assert_trail(blog.title)
  end

  test 'owner settings with no legacy breadcrumbs include the circle' do
    login(@owner)
    get inquiry_settings_path(@circle)
    assert_response :success
    assert_trail('お問い合わせ設定')
    assert_select '.breadcrumbs a[href=?]', circle_path(@circle), text: @circle.name
  end

  test 'legacy form trails have only one current page' do
    login(@owner)
    get new_user_schedule_path(@circle)
    assert_response :success
    assert_trail('スケジュールの新規追加')
    assert_select '.breadcrumbs a[href=?]', circle_path(@circle), text: @circle.name
  end

  test 'event discovery shares the accessible trail without duplicate navigation' do
    get '/dates/today'
    assert_response :success
    assert_select 'nav.breadcrumbs[aria-label="パンくずリスト"]', count: 1
    assert_select '.breadcrumbs [aria-current=page]', count: 1
    assert_select '.breadcrumbs a[href="/dates"]', text: 'イベント開催予定'
  end

  test 'all application GET routes have a breadcrumb label fallback' do
    excluded = %w[healthcheck sitemaps listing_images chat_images redirect]
    Rails.application.routes.routes.each do |route|
      next unless route.verb.include?('GET')
      controller = route.defaults[:controller]
      next unless controller && !excluded.include?(controller)
      next if controller.start_with?('rails/', 'active_storage/', 'action_mailbox/')
      section = controller.split('/').last
      known = BreadcrumbsHelper::BREADCRUMB_SECTIONS.key?(section) || BreadcrumbsHelper::BREADCRUMB_LABELS.key?(section) ||
        %w[home pages sessions registrations passwords confirmations unlocks].include?(section)
      assert known, "パンくずのページ名が未設定: #{controller}##{route.defaults[:action]}"
    end
  end

  private

  def login(owner)
    post admin_user_session_path, params: { admin_user: { email: owner.email, password: 'test-password-123' } }
    assert_response :redirect
  end

  def assert_trail(label)
    assert_select 'nav.breadcrumbs[aria-label="パンくずリスト"]', count: 1
    assert_select '.breadcrumbs ol', count: 1
    assert_select '.breadcrumbs [aria-current=page]', text: label, count: 1
    assert_select '.breadcrumbs li:last-child a', count: 0
  end
end
