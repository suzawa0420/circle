require 'test_helper'
require_relative '../support/chat_records'

class WebmasterOpinionsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    @master = Webmaster.create!(id: 1, email: 'webmaster@example.test', password: 'test-password-123')
  end

  test 'only webmaster can read opinions' do
    Opinion.create!(user: @circle, opinion: '運営への非公開のご意見')
    get super_admin_opinions_path
    assert_redirected_to new_webmaster_session_path
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    get super_admin_opinions_path
    assert_redirected_to new_webmaster_session_path
    post member_session_path, params: { member: { email: @member.email, password: 'test-password-123' } }
    get super_admin_opinions_path
    assert_redirected_to new_webmaster_session_path
    login_master
    get super_admin_opinions_path
    assert_response :success
    assert_includes response.body, '運営への非公開のご意見'
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_equal 'noindex, nofollow', response.headers['X-Robots-Tag']
    assert_not_includes response.body, 'googletagmanager'
  end

  test 'list shows full escaped text, circle links, dates and missing circles without changing posts' do
    text = "ご意見の一行目\n二行目 <script>alert(1)</script> <img src=x onerror=alert(1)>\n" + '長い本文です。' * 100
    opinion = Opinion.create!(user: @circle, opinion: text, created_at: Time.zone.local(2026, 10, 1, 12, 34))
    Opinion.create!(opinion: '投稿元がない過去のご意見')
    # Legacy rows can also retain an ID for a deleted circle.
    Opinion.create!(user_id: User.maximum(:id) + 1000, opinion: '削除済みサークルのご意見')
    login_master
    assert_no_difference('Opinion.count') do
      assert_no_difference('ActionMailer::Base.deliveries.size') { get super_admin_opinions_path }
    end
    assert_response :success
    assert_select "article a[href='#{circle_path(@circle)}']", text: @circle.name
    assert_select ".wm-submission-author a[href='#{super_admin_account_path(@owner, kind: 'owner')}']"
    assert_select '.wm-submission-author', text: /投稿元サークルの現在の主催者/
    assert_includes response.body, '2026/10/01 12:34'
    assert_includes response.body, '長い本文です。' * 100
    assert_select '.wm-body br', minimum: 1
    assert_select '.wm-body script, .wm-body img, .wm-body [onerror]', count: 0
    assert_select 'article h3', text: '投稿元サークルなし（削除済み・不明）', count: 2
    assert_equal text, opinion.reload.opinion
  end

  test 'list is paginated in stable newest order and navigation links to it' do
    timestamp = Time.current
    posts = 31.times.map { |i| Opinion.create!(opinion: "ご意見 #{i}", created_at: timestamp) }
    login_master
    get webmaster_path
    assert_select ".webmaster-grid a[href='#{super_admin_opinions_path}']"
    assert_select ".webmaster-subnav a[href='#{super_admin_opinions_path}']"
    get super_admin_opinions_path
    assert_select 'article.webmaster-card', count: 30
    assert_includes response.body, '全 31 件'
    ids = css_select('article .wm-meta').map { |node| node.text[/投稿ID：(\d+)/, 1].to_i }
    assert_equal posts.reverse.first(30).map(&:id), ids
    get super_admin_opinions_path, params: { page: 2 }
    assert_select 'article.webmaster-card', count: 1
    assert_includes response.body, 'ご意見 0'
  end

  test 'empty list explains that no opinions have arrived' do
    login_master
    get super_admin_opinions_path
    assert_response :success
    assert_includes response.body, 'ご意見はまだありません。'
  end

  private

  def login_master
    post webmaster_session_path, params: { webmaster: { email: @master.email, password: 'test-password-123' } }
  end
end
