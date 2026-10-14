require 'test_helper'
require_relative '../support/chat_records'

class BreadcrumbsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    @circle.update!(recruitment: '初心者歓迎')
  end

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

  test 'public trails output exactly one BreadcrumbList matching visible labels and links' do
    ['/about', '/faq', circle_path(@circle), '/circles'].each do |path|
      get path, params: { utm_source: 'breadcrumb-test' }
      assert_response :success
      assert_structured_trail
    end
  end

  test 'legacy category links use the category slug in HTML and JSON-LD' do
    get "/categories/#{@circle.category.kana}/#{@circle.prefecture.kana}"
    assert_response :success
    assert_structured_trail
    assert_select '.breadcrumbs a[href=?]', "/categories/#{@circle.category.kana}", text: @circle.category.name
  end

  test 'legacy genre and region links point directly to current routes' do
    tag = Tag.create!(name: '初心者歓迎', text: '初心者歓迎')
    @circle.tags << tag
    get "/#{@circle.event.ruby}/#{@circle.prefecture.kana}/tag/#{tag.id}"
    assert_response :success
    assert_structured_trail
    assert_select '.breadcrumbs a[href=?]', event_path(@circle.event.ruby), text: @circle.event.name
    assert_select '.breadcrumbs a[href=?]', event_prefecture_path(@circle.event.ruby, @circle.prefecture.kana), text: @circle.prefecture.name
  end

  test 'current URL preserves canonical pagination and excludes sort and tracking parameters' do
    get circle_path(@circle), params: { page: '2', sort: '2', utm_source: 'campaign', gclid: 'tracking' }
    assert_response :success
    assert_equal "https://circle-book.com#{circle_path(@circle)}?page=2", breadcrumb_nodes.first['itemListElement'].last['item']
  end

  test 'JSON-LD safely serializes quotes backslashes and script closing tags' do
    name = 'サークル "募集" \\ </script><script>alert(1)</script>'
    @circle.update!(name: name)
    get circle_path(@circle)
    assert_response :success
    assert_structured_trail
    assert_equal name, breadcrumb_nodes.first['itemListElement'].last['name']
    assert_select 'script', text: 'alert(1)', count: 0
  end

  test 'private routes noindex pages and home do not advertise breadcrumb rich results' do
    ['/', '/members/sign_in', '/support/new', '/places/all', '/dates/today'].each do |path|
      get path
      assert_response :success
      assert_empty breadcrumb_nodes, path
    end
    login(@owner)
    get inquiry_settings_path(@circle)
    assert_response :success
    assert_empty breadcrumb_nodes
  end

  test 'event schema uses the shared trail once and retains the event ItemList' do
    @circle.schedules.create!(day: Date.current.iso8601, title: '公開練習会', venue: '体育館', time_s: '18:00', time_e: '21:00')
    get '/dates/today'
    assert_response :success
    assert_structured_trail
    assert structured_nodes.any? { |data| data['@type'] == 'ItemList' }
  end

  test 'facility schema keeps LocalBusiness and uses only the shared breadcrumb' do
    city = City.create!(name: '目黒区', city_kana: 'breadcrumb-meguro', prefecture: @circle.prefecture)
    place = Place.create!(name: 'パンくず検証体育館', prefecture: @circle.prefecture, city: city,
      user_id: @circle.id, address: '目黒区1-1', tag: '体育館', events: [@circle.event])
    ["/places/#{@circle.event.ruby}", "/places/#{@circle.event.ruby}/#{@circle.prefecture.kana}/#{city.city_kana}/#{place.id}"].each do |path|
      get path
      assert_response :success
      assert_structured_trail
    end
    assert structured_nodes.any? { |data| data['@type'] == 'LocalBusiness' }
  end

  test 'public breadcrumb appears above footer links including event pages' do
    ['/about', '/dates/today'].each do |path|
      get path
      assert_response :success
      assert_select 'footer .footer_wrap > .breadcrumbs_wrapper:first-of-type', count: 1
      assert_select '.event-results .breadcrumbs_wrapper', count: 0
      footer = css_select('footer .footer_wrap').sole
      assert_includes footer.element_children.first['class'].to_s, 'breadcrumbs_wrapper'
    end
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

  def structured_nodes
    css_select('script[type="application/ld+json"]').flat_map do |node|
      data = JSON.parse(node.text)
      data.is_a?(Hash) && data['@graph'] ? data['@graph'] : Array.wrap(data)
    end
  end

  def breadcrumb_nodes
    structured_nodes.select { |data| data['@type'] == 'BreadcrumbList' }
  end

  def assert_structured_trail
    assert_equal 1, breadcrumb_nodes.length
    items = breadcrumb_nodes.first['itemListElement']
    visible = css_select('.breadcrumbs li').map { |node| node.text.strip }
    assert_equal visible, items.map { |item| item['name'] }
    assert_equal (1..items.length).to_a, items.map { |item| item['position'] }
    assert items.all? { |item| item['@type'] == 'ListItem' }
    assert_operator items.length, :>=, 2
    links = css_select('.breadcrumbs a').map { |node| 'https://circle-book.com' + node['href'] }
    assert_equal links, items[0...-1].map { |item| item['item'] }
    assert items[0...-1].all? { |item| item['item'].start_with?('https://circle-book.com/') }
    canonical_link = css_select('link[rel=canonical]').first
    canonical = URI.parse(canonical_link ? canonical_link['href'] : request.path)
    assert_equal 'https://circle-book.com' + canonical.path, items.last['item']
    refute items.any? { |item| item['item'].to_s.include?('utm_source') }
  end

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
