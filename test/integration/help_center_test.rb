require 'test_helper'
require_relative '../support/chat_records'

class HelpCenterTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup { create_chat_records }

  test 'help is public and categories and all article action links render' do
    get faq_path
    assert_response :success
    assert_select 'h1', text: 'ヘルプセンター'
    assert_select 'input[name=help_query]'
    assert_select 'select[name=audience] option', count: 3
    assert_not_includes response.body, 'googletagmanager'
    HelpCatalog::ARTICLES.each do |article|
      get help_article_path(article[:id])
      assert_response :success, article[:id]
      assert_select 'h1', text: article[:title]
      assert_select '.help-answer p'
      assert_select 'form[action$="/feedback"]'
    end
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    get help_article_path('edit-listing')
    assert_select "a[href='/users/#{@circle.id}/mypage']"
    assert_raises(ActiveRecord::RecordNotFound) { get help_article_path('missing') }
  end

  test 'long answers have semantic headings steps and searchable section text' do
    get help_article_path('reviews')
    assert_select '.help-answer h2', text: '現在の口コミ（メッセージでやり取りした参加者の投稿）'
    assert_select '.help-answer h2', text: '旧口コミ（以前の匿名投稿）'
    assert_select '.help-answer p', minimum: 3
    assert_select '.help-answer ol li', count: 3
    get help_article_path('owner-reply')
    assert_select '.help-answer h2', text: '現在のお問い合わせへの返信手順'
    assert_select '.help-answer ol li', count: 3
    get faq_path(help_query: '旧口コミ 匿名')
    assert_select "a[href='#{help_article_path('reviews')}']"
    get faq_path(help_query: '現在のお問い合わせへの返信手順')
    assert_select "a[href='#{help_article_path('owner-reply')}']"
  end

  test 'answer headings paragraphs and steps escape HTML' do
    html = ApplicationController.render(partial: 'help_center/answer', locals: { article: { content: [
      { heading: '<script>bad()</script>' }, { paragraph: '<img src=x onerror=bad()>' },
      { steps: ['<script>bad()</script>'] }
    ] } })
    fragment = Nokogiri::HTML.fragment(html)
    assert_empty fragment.css('script, img, [onerror]')
    assert_equal '<script>bad()</script>', fragment.at_css('h2').text
    assert_equal '<img src=x onerror=bad()>', fragment.at_css('p').text
    assert_equal '<script>bad()</script>', fragment.at_css('li').text
  end

  test 'search is normalized and audience/category filters and no-result guidance work without javascript' do
    get faq_path
    token = css_select('input[name=spam_form_token]').first['value']
    assert_difference('HelpEvent.count', 1) do
      post help_search_path, params: { spam_form_token: token, help_query: '　パスワード　', audience: 'member', category: 'account' }
    end
    assert_response :see_other
    follow_redirect!
    assert_response :success
    assert_includes response.body, 'ログインできない・パスワードを忘れた'
    assert_not_includes response.body, '主催者アカウントを退会したい'
    assert_equal 'search', HelpEvent.last.kind
    assert HelpEvent.last.result_count.positive?
    assert_equal 'パスワード', HelpEvent.last.query
    get faq_path(help_query: '存在しない質問のことば')
    assert_includes response.body, '一致する回答が見つかりませんでした。'
    get faq_path(help_query: '<script>alert(1)</script>')
    assert_select 'script', text: 'alert(1)', count: 0
  end

  test 'search requires signed token and does not store obvious personal information' do
    assert_no_difference('HelpEvent.count') { post help_search_path, params: { help_query: '検索' } }
    assert_response :unprocessable_entity
    get faq_path
    token = css_select('input[name=spam_form_token]').first['value']
    post help_search_path, params: { spam_form_token: token, help_query: 'someone@example.test' }
    assert_equal '（個人情報を含む可能性のため記録省略）', HelpEvent.last.query
  end

  test 'answer evaluation is bounded to one per browser article day and retention is 90 days' do
    get help_article_path('login')
    token = css_select('form[action$="/feedback"] input[name=spam_form_token]').first['value']
    post help_feedback_path('login'), params: { spam_form_token: token, answer: 'helpful' }
    assert_response :see_other
    assert_equal 1, HelpEvent.count
    post help_feedback_path('login'), params: { spam_form_token: token, answer: 'unhelpful' }
    assert_equal 1, HelpEvent.count
    assert_equal 'unhelpful', HelpEvent.last.kind
    assert_no_difference('HelpEvent.count') { post help_feedback_path('login'), params: { spam_form_token: token, answer: 'fake' } }
    old = HelpEvent.create!(kind: 'search', query: '古い検索', visitor_key: 'old', recorded_on: 91.days.ago.to_date, created_at: 91.days.ago)
    ChatMaintenance.run
    assert_not HelpEvent.exists?(old.id)
    assert_equal 1, HelpEvent.count
  end

  test 'contextual help is available on login edit and message screens' do
    get new_member_session_path
    assert_select "a[href='#{help_article_path('login')}']"
    get new_member_password_path
    assert_select "a[href='#{help_article_path('reset-mail')}']"
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    get edit_user_path(@circle)
    assert_select "a[href='#{help_article_path('edit-listing')}']"
    get conversation_path(@conversation)
    assert_select "a[href='#{help_article_path('message-notification')}']"
  end
end
