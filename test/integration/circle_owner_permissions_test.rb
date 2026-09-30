require 'test_helper'

class CircleOwnerPermissionsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    category = Category.create!(name: '球技', kana: 'owner-permissions', order: '1')
    event = Event.create!(name: 'バスケ', ruby: 'owner-basketball', category: category, order: '1')
    prefecture = Prefecture.create!(name: '東京都', kana: 'owner-tokyo', order: '1', sort: 1)
    @owner = AdminUser.create!(email: 'circle-owner@example.test', password: 'test-password-123')
    @other = AdminUser.create!(email: 'other-owner@example.test', password: 'test-password-123')
    @circle = User.create!(name: '管理検証サークル', appeal: '地域で定期的に練習しています。初心者も経験者も歓迎します。' * 6,
                           event: event, prefecture: prefecture, category: category, admin_user: @owner,
                           area: '世田谷区', schedule: '毎週土曜', switch: '募集中')
    @other_circle = User.create!(name: '別のサークル', appeal: '地域で定期的に練習しています。初心者も経験者も歓迎します。' * 6,
                                 event: event, prefecture: prefecture, category: category, admin_user: @other,
                                 area: '渋谷区', schedule: '毎週日曜', switch: '募集中')
    @blog = Blog.create!(user: @circle, title: '活動報告', content: '練習を行いました。' * 20)
    @question = Question.create!(user: @circle, content: '参加できますか？')
  end

  test 'owner can edit their circle and profile and delete its blog question and circle' do
    sign_in_as(@owner)

    get circle_path(@circle)
    assert_response :success
    assert_select "a[href='#{user_path(@circle)}'][data-method='delete']"

    get edit_user_path(@circle)
    assert_response :success
    patch user_path(@circle), params: { user: { name: '更新したサークル' } }
    assert_response :redirect
    assert_equal '更新したサークル', @circle.reload.name

    patch "/users/#{@circle.id}/edit3", params: { admin_user: { nickname: '新しい名前' } }
    assert_response :redirect
    assert_equal '新しい名前', @owner.reload.nickname

    get edit_circle_blog_path(@circle, @blog)
    assert_response :success
    token = Nokogiri::HTML(response.body).at_css('input[name="spam_form_token"]')['value']
    patch circle_blog_path(@circle, @blog), params: {
      blog: { title: '更新した活動報告' }, spam_form_token: token, contact_website: ''
    }
    assert_response :redirect
    assert_equal '更新した活動報告', @blog.reload.title
    delete circle_blog_path(@circle, @blog)
    assert_response :redirect
    assert_not Blog.exists?(@blog.id)

    patch user_question_path(@circle, @question), params: { question: { answer: 'ぜひ参加してください' } }
    assert_response :redirect
    assert_equal 'ぜひ参加してください', @question.reload.answer
    delete user_question_path(@circle, @question)
    assert_response :redirect
    assert_not Question.exists?(@question.id)

    delete user_path(@circle)
    assert_response :redirect
    assert_not User.exists?(@circle.id)
    assert User.exists?(@other_circle.id)
  end

  test 'another owner cannot change or delete the circle or its content' do
    assert_not_equal @other.id, @circle.admin_user_id
    assert_not @other.master_account?
    sign_in_as(@other)

    patch user_path(@circle), params: { user: { name: '不正変更' } }
    assert_response :redirect
    assert_equal '管理検証サークル', @circle.reload.name

    patch "/users/#{@circle.id}/edit3", params: { admin_user: { nickname: '不正変更' } }
    assert_response :redirect
    assert_nil @owner.reload.nickname

    delete user_path(@circle)
    assert_response :redirect
    assert User.exists?(@circle.id)

    delete circle_blog_path(@circle, @blog)
    assert_response :forbidden
    assert Blog.exists?(@blog.id)

    patch circle_blog_path(@circle, @blog), params: { blog: { title: '不正変更' } }
    assert_response :forbidden
    assert_equal '活動報告', @blog.reload.title

    patch user_question_path(@circle, @question), params: { question: { answer: '不正変更' } }
    assert_response :forbidden
    assert_nil @question.reload.answer

    delete user_question_path(@circle, @question)
    assert_response :forbidden
    assert Question.exists?(@question.id)
  end

  test 'anonymous visitors cannot delete a circle or its content' do
    delete user_path(@circle)
    assert_redirected_to new_admin_user_session_path
    delete circle_blog_path(@circle, @blog)
    assert_redirected_to new_admin_user_session_path
    delete user_question_path(@circle, @question)
    assert_redirected_to new_admin_user_session_path
    assert User.exists?(@circle.id)
    assert Blog.exists?(@blog.id)
    assert Question.exists?(@question.id)
  end

  test 'posting restriction does not prevent the owner from editing or removing existing blogs' do
    @owner.update!(check: 1)
    sign_in_as(@owner)

    get new_circle_blog_path(@circle)
    assert_response :forbidden
    get edit_circle_blog_path(@circle, @blog)
    assert_response :success
    delete circle_blog_path(@circle, @blog)
    assert_response :redirect
    assert_not Blog.exists?(@blog.id)
  end

  private

  def sign_in_as(admin_user)
    post admin_user_session_path, params: { admin_user: { email: admin_user.email, password: 'test-password-123' } }
    assert_response :redirect
  end
end
