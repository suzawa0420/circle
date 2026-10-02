require 'test_helper'
require_relative '../support/chat_records'

class SiteDesignTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup { create_chat_records }

  test 'public pages share the design scope and a Japanese document language' do
    [root_path, circles_path, '/blogs', '/matches', '/places', '/about', '/faq', '/rules', '/privacypolicy', '/login'].each do |path|
      get path
      assert_response :success, path
      assert_select 'html[lang=ja]', count: 1
      assert_select 'body.cb-site', count: 1
      assert_select 'h1', minimum: 1
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
    assert_select 'select[name=event_select][aria-label]'
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
  private

  def login(owner)
    post admin_user_session_path, params: { admin_user: { email: owner.email, password: 'test-password-123' } }
    assert_response :redirect
  end

end
