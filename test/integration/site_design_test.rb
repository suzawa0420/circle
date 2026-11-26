require 'test_helper'
require_relative '../support/chat_records'

class SiteDesignTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup { create_chat_records }

  test 'schedule header links both the circle name and icon to details in a new tab' do
    schedule = @circle.schedules.create!(title: '週末の練習', venue: '体育館', day: (Date.current + 7).to_s)
    [user_schedule_path(@circle, schedule), circle_path(@circle)].each do |path|
      get path
      assert_response :success
      assert_select '.mobile-circle-summary__identity a.mobile-circle-summary__profile[href=?][target="_blank"][rel="noopener"]', circle_path(@circle), count: 1 do
        assert_select 'h2', text: @circle.name
        assert_select '.mobile-circle-summary__image', count: 1
        assert_select '.mobile-circle-summary__bookmark', count: 0
      end
      assert_select '.mobile-circle-summary__bookmark', count: 1
    end
    get user_schedules_path(@circle)
    assert_response :success
    assert_select 'a.cb-public-circle__profile[href=?][target="_blank"][rel="noopener"]', circle_path(@circle), count: 1 do
      assert_select '.cb-public-circle__name', text: @circle.name
      assert_select '.cb-public-circle__avatar', count: 1
    end
    assert_select '[id^=mobile-circle-bookmark-]', count: 1
  end

  test 'circle cover shows the stored update date with Japanese weekday, including without a photo' do
    @circle.update_column(:user_time, Time.zone.local(2026, 11, 26, 12))
    get circle_path(@circle)
    assert_response :success
    assert_select '.circle-detail-cover time[datetime="2026-11-26"]', text: "2026年11月26日（木）", count: 1
    assert_select 'time[datetime="2026-11-26"]', count: 1
    assert_select '.cb-detail-identity time', count: 0
    assert_select '.circle-detail-cover .ribbon', text: "募集中", count: 1
    assert_select '.circle-detail-cover__tags', count: 1

    @circle.update_column(:user_time, nil)
    get circle_path(@circle)
    assert_response :success
    assert_select '.circle-detail-cover time', count: 0
  end

  test 'circle navigation hides unavailable tabs without hiding the current page or owner entry points' do
    tabs = -> { css_select('nav[aria-label="サークル内のページ"] > a').map { |link| link.text.strip } }
    get circle_path(@circle)
    assert_response :success
    assert_equal ["詳細", "Q&A"], tabs.call

    get user_reviews_path(@circle)
    assert_response :success
    assert_equal ["詳細", "口コミ", "Q&A"], tabs.call
    assert_select 'nav[aria-label="サークル内のページ"] > a[aria-current=page]', text: "口コミ"

    get user_schedules_path(@circle)
    assert_response :success
    assert_equal ["詳細", "活動日", "Q&A"], tabs.call
    assert_select 'nav[aria-label="サークル内のページ"] > a[aria-current=page]', text: "活動日"

    get circle_blogs_path(@circle)
    assert_response :success
    assert_equal ["詳細", "Q&A", "ブログ"], tabs.call
    assert_select 'nav[aria-label="サークル内のページ"] > a[aria-current=page]', text: "ブログ"

    @circle.schedules.create!(title: "練習", venue: "体育館", day: (Date.current + 7).iso8601)
    @circle.blogs.create!(title: "確認中", content: "公開前の記事" * 25, moderation_status: "pending")
    get circle_path(@circle)
    assert_equal ["詳細", "活動日", "Q&A"], tabs.call
    assert_select 'nav[aria-label="サークル内のページ"] > [aria-disabled=true]', count: 0

    @circle.reviews.create!(member: @member, review: 1, comment: "楽しかったです")
    @circle.blogs.create!(title: "公開記事", content: "活動の記録" * 25)
    get circle_path(@circle)
    assert_equal ["詳細", "活動日", "口コミ", "Q&A", "ブログ"], tabs.call

    @circle.schedules.delete_all
    @circle.reviews.delete_all
    @circle.blogs.delete_all
    login(@owner)
    get circle_path(@circle)
    assert_response :success
    assert_equal ["詳細", "活動日", "Q&A", "ブログ"], tabs.call
  end

  test 'public circle pages share scroll navigation, the mobile footer and the same inquiry entry point' do
    @circle.update_column(:name, '長いサークル名' * 12)
    routes = {
      '詳細' => circle_path(@circle),
      '活動日' => user_schedules_path(@circle),
      '口コミ' => user_reviews_path(@circle),
      'Q&A' => user_questions_path(@circle),
      'ブログ' => circle_blogs_path(@circle)
    }
    routes.each do |label, path|
      get path
      assert_response :success
      assert_select 'body.circle-scroll-header .circle-header-sentinel', count: 1
      assert_select 'nav[aria-label="サークル内のページ"] [aria-current="page"]', text: label, count: 1
      assert_select 'nav.mobile-bottom-nav', count: 1
      assert_select '.cb-public-circle__sticky-profile .cb-public-circle__name[title=?]', @circle.name, count: 1 unless label == '詳細'
      assert_select '.cb-public-circle__sticky-actions a[aria-label="無料参加者登録してサークルを保存"]', count: 1
      assert_select 'a.cb-public-circle__sticky-inquiry[data-circle-inquiry-click=true][aria-label="このサークルにお問い合わせ"]', count: 1 do |links|
        assert_equal new_user_conversation_path(@circle), URI.parse(links.first['href']).path
        assert_includes links.first.inner_html, 'cb-icon--mail'
      end
      assert_select 'a.cb-public-circle__floating-inquiry.cb-participant[data-circle-inquiry-click=true][aria-label="このサークルにお問い合わせ"]', count: 1 do |links|
        assert_includes links.first.inner_html, 'cb-icon--mail'
        assert_equal new_user_conversation_path(@circle), URI.parse(links.first['href']).path
      end
      if label == '詳細'
        assert_select '.cb-detail-primary a.mobile-circle-summary__cta svg.cb-icon--mail', count: 1
      else
        assert_select '.cb-public-circle__action-panel a.cb-public-circle__primary svg.cb-icon--mail', count: 1
      end
    end
  end

  test 'floating inquiry is absent on the owner view and when recruitment is closed' do
    @circle.update_column(:switch, '募集終了')
    get circle_path(@circle)
    assert_response :success
    assert_select '.cb-public-circle__floating-inquiry, .cb-public-circle__sticky-inquiry', count: 0

    @circle.update_column(:switch, '募集中')
    login(@owner)
    get circle_path(@circle)
    assert_response :success
    assert_select '.cb-public-circle__floating-inquiry, .cb-public-circle__sticky-inquiry', count: 0
  end

  test 'circle details keeps one save control in the same place across account states' do
    get circle_path(@circle)
    assert_response :success
    assert_select '.mobile-circle-summary__bookmark .mobile-circle-save.cb-participant[href=?]', new_member_registration_path, count: 1
    assert_select '.bookmark_btn_wrap', count: 0

    post member_session_path, params: { member: { email: @member.email, password: 'test-password-123' } }
    assert_response :redirect
    get circle_path(@circle)
    assert_select '.mobile-circle-summary__bookmark .mobile-circle-save.cb-participant[data-method=post]', count: 1

    post user_bookmarks_path(@circle), xhr: true
    assert_response :success
    assert_includes response.body, "mobile-circle-bookmark-#{@circle.id}"
    assert_includes response.body, '保存済み'
    get circle_path(@circle)
    assert_select '.mobile-circle-summary__bookmark .mobile-circle-save.cb-participant[data-method=delete]', text: '保存済み', count: 1

    delete user_bookmarks_path(@circle), xhr: true
    assert_response :success
    get circle_path(@circle)
    assert_select '.mobile-circle-summary__bookmark .mobile-circle-save[data-method=post]', count: 1

    delete destroy_member_session_path
    login(@owner)
    get circle_path(@circle)
    assert_select '.mobile-circle-summary__bookmark .mobile-circle-save[href=?]', new_member_registration_path, count: 1
  end

  test 'the public organizer introduction preserves line breaks and paragraphs' do
    @owner.update_columns(open: 1, nickname: '主催者', profile: "最初の行\r\n次の行\r\n\r\n別の段落")
    get circle_path(@circle)
    assert_response :success
    assert_select '.cb-detail-organizer__bio p', count: 2
    assert_select '.cb-detail-organizer__bio p:first-child br', count: 1
    assert_select '.cb-detail-organizer__bio p:last-child', text: '別の段落'
  end

  test 'circle detail cover has purpose-built tags and owner actions' do
    second = Prefecture.create!(name: '神奈川県', kana: 'chat-kanagawa', order: '2', sort: 2)
    @circle.update_column(:prefecture_sub_id, second.id)
    get circle_path(@circle)
    assert_select '.circle-detail-cover__tags span', count: 3
    assert_select '.circle-detail-cover__tags span', text: '神奈川県'
    assert_select '.circle-detail-cover__actions button.circle-detail-cover__action--share', count: 1
    assert_select '.circle-detail-cover__actions a.circle-detail-cover__action--edit', count: 0

    login(@owner)
    get circle_path(@circle)
    assert_select '.circle-detail-cover__actions a.circle-detail-cover__action--edit[href=?]', edit_user_path(@circle), text: 'プロフィール編集', count: 1
  end

  test 'the circle detail share menu offers three external destinations and a clean public URL' do
    get circle_path(@circle), params: { source: 'tracking-example' }
    assert_response :success
    assert_select 'button[data-circle-share-open][aria-controls="circle-detail-share-dialog"]', text: '共有', count: 1
    assert_select 'dialog#circle-detail-share-dialog', count: 1 do
      assert_select 'a[href^="https://twitter.com/intent/tweet?"][rel="noopener noreferrer"]', text: 'Xで共有'
      assert_select 'a[href^="https://www.threads.com/intent/post?"]', text: 'Threadsで共有'
      assert_select 'a[href^="https://social-plugins.line.me/lineit/share?"]', text: 'LINEで共有'
      assert_select 'button[data-circle-share-copy]', text: 'URLをコピー'
      assert_select 'input[readonly][value=?]', circle_url(@circle)
    end
  end

  test 'blog list retains the complete long circle name for accessible single line display' do
    name = '【参加費0円】散策で友達作り！カフェ・ランチや都内イベントに一緒に行こう'
    @circle.update_column(:name, name)
    @circle.blogs.create!(title: '週末の活動記録', content: '参加者のみなさんと楽しく活動しました。' * 8)
    ['/blogs', circle_blogs_path(@circle)].each do |path|
      get path
      assert_response :success
      assert_select '.cb-circle-blogs__card .cb-circle-blogs__author[title=?]', name, text: name, count: 1
    end
  end

  test 'owner dashboard renders Lucide actions including additional circle registration' do
    login(@owner)
    get "/users/#{@circle.id}/mypage"
    assert_response :success
    assert_select '.dashboard-action svg.cb-icon--plus', count: 1
    assert_select '.dashboard-action svg.cb-icon', minimum: 5
    assert_select '.fa', count: 0
  end

  test 'public pages share the design scope and a Japanese document language' do
    [root_path, circles_path, '/blogs', '/matches', '/places', '/about', '/faq', '/rules', '/privacypolicy', '/login'].each do |path|
      get path
      assert_response :success, path
      assert_select 'html[lang=ja]', count: 1
      assert_select 'body.cb-site', count: 1
      assert_select 'h1', minimum: 1
      assert_select 'link[rel=manifest][href="/manifest.webmanifest"]', count: 1
      assert_select '[data-home-screen-install][aria-controls=home-screen-install-dialog]', count: 2
      assert_select 'dialog#home-screen-install-dialog[aria-labelledby=home-screen-install-title]', count: 1
      assert_select '[data-install-instructions=ios] li', count: 3
    end
  end

  test 'search sorting preserves the keyword and drops a stale page number' do
    get circles_search_index_path, params: { q: @circle.name, sort: '2', page: '1' }
    assert_response :success
    assert_select '.cb-sort [aria-current=true]', text: '人気順'
    assert_select '.cb-sort a' do |links|
      links.each do |link|
        query = Rack::Utils.parse_nested_query(URI.parse(link['href']).query)
        assert_equal @circle.name, query['q']
        assert_nil query['page']
      end
    end
    assert_select 'input[name=q][aria-label]'
    assert_select 'select[name=event_id][aria-label]'
  end

  test 'circle editing has one named heading and retains the circle switcher' do
    login(@owner)
    get edit_user_path(@circle)
    assert_response :success
    assert_select 'h1', count: 1, text: 'サークルの基本情報'
    assert_select '.management-circle-trigger'
    assert_select 'form input[name="user[name]"]'
  end

  test 'question edit opens the answer form on its detail page' do
    question = @circle.questions.create!(content: '一人でも参加できますか？')
    login(@owner)
    get edit_user_question_path(@circle, question)
    assert_redirected_to user_question_path(@circle, question)
    follow_redirect!
    assert_response :success
    assert_select 'h1', count: 1, text: question.content
    assert_select 'textarea[name="question[answer]"]'
  end
  test 'participant entry points have an explicit role without recoloring organizer entry points' do
    get '/login'
    assert_response :success
    assert_select '.login-choice__card.cb-participant #participant-login-title', count: 1
    assert_select '.login-choice__card.cb-participant #organizer-login-title', count: 0
    get circle_path(@circle)
    assert_response :success
    assert_select '.mobile-circle-summary__bookmark .mobile-circle-save[href=?]', new_member_registration_path, count: 1
    assert_select '.mobile-circle-summary__image--empty', text: 'チ'
    assert_select '.circle-avatar--empty.cb-detail-avatar__image', text: 'チ'
    get user_schedules_path(@circle)
    assert_select '.mobile-circle-save.cb-participant', count: 2
  end

  test 'participant chat scope and author identities remain distinct' do
    accept_conversation
    post member_session_path, params: { member: { email: @member.email, password: 'test-password-123' } }
    get conversation_path(@conversation)
    assert_response :success
    assert_select '.chat-shell.cb-participant', count: 1
    assert_select '.chat-avatar--owner', minimum: 1
    assert_select '.chat-message--member', minimum: 1
    assert_select '.message-role--member', minimum: 1
    assert_select '.message-role--owner', minimum: 1
    assert_select '.chat-message--owner', minimum: 1
    delete destroy_member_session_path
    login(@owner)
    get conversation_path(@conversation)
    assert_response :success
    assert_select '.chat-shell.cb-participant', count: 0
    assert_select '.chat-avatar--member', minimum: 1
  end

  test 'platform notices are separate from organizer automatic guidance' do
    login(@owner)
    get conversation_path(@conversation)
    assert_response :success
    assert_select '#chat-acceptance-status.cb-system-notice .cb-system-notice__label', text: 'システム通知'
    assert_select '.inquiry-guidance__message.cb-system-notice', count: 0
    get admin_user_email_verification_path
    assert_response :success
    assert_select '.cb-system-panel', count: 1
    assert_select '.cb-system-notice', minimum: 1
  end

  private

  def login(owner)
    post admin_user_session_path, params: { admin_user: { email: owner.email, password: 'test-password-123' } }
    assert_response :redirect
  end

end
