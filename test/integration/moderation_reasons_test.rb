require 'test_helper'
require_relative '../support/chat_records'

class ModerationReasonsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords
  setup do
    create_chat_records
    @master = Webmaster.create!(id: 1, email: 'reasons-master@example.test', password: 'test-password-123')
    @content = 'みんなで楽しく活動しました。定期的に練習しています。初心者も歓迎しています。' * 5
  end

  test 'duplicate and frequent posting reasons are saved with the decision timestamp' do
    first = @circle.blogs.create!(title: '活動報告1', content: @content)
    second = @circle.blogs.create!(title: '活動報告2', content: @content)
    third = @circle.blogs.create!(title: '活動報告3', content: @content)
    fourth = @circle.blogs.create!(title: '活動報告4', content: @content)
    assert_equal 'clear', first.moderation_status
    assert_equal 'clear', second.moderation_status
    assert_equal ['duplicate_content'], third.reload.moderation_reasons.map { |r| r['code'] }
    assert_equal %w[duplicate_content frequent_posts], fourth.reload.moderation_reasons.map { |r| r['code'] }
    assert fourth.moderation_checked_at
    saved = fourth.moderation_reasons
    stamp = fourth.moderation_checked_at
    travel 2.hours
    fourth.update!(content: @content + '次回の活動も楽しみです。')
    assert_equal 'review', fourth.reload.moderation_status
    assert_equal saved, fourth.moderation_reasons
    assert_equal stamp, fourth.moderation_checked_at
  end

  test 'foreign language links and circle language decisions record exact reasons' do
    blog = @circle.blogs.create!(title: 'Weekly report', content: 'Read https://one.example.test and https://two.example.test ' * 5)
    assert_equal ['foreign_links'], blog.reload.moderation_reasons.map { |r| r['code'] }
    @circle.update!(name: 'Practice club', appeal: 'This is a local activity club. ' * 10)
    assert_equal ['non_japanese_profile'], @circle.reload.moderation_reasons.map { |r| r['code'] }
    assert @circle.moderation_checked_at
    @circle.update_column(:moderation_status, 'blocked')
    @circle.update!(name: '日本語のサークル')
    assert_equal 'blocked', @circle.reload.moderation_status
    assert_equal ['non_japanese_profile'], @circle.moderation_reasons.map { |r| r['code'] }
  end

  test 'master sees reasons on queue blog circle and organizer details without changing decisions' do
    blog = @circle.blogs.create!(title: 'Weekly report', content: 'Read https://one.example.test and https://two.example.test ' * 5)
    @circle.update!(name: 'Practice club', appeal: 'This is a local activity club. ' * 10)
    login_master
    before = [blog.reload.moderation_status, @circle.reload.moderation_status]
    [super_admin_circles_path, super_admin_accounts_path(kind: 'owner'), super_admin_account_path(@owner, kind: 'owner'), circle_path(@circle)].each do |path|
      get path
      assert_response :success
      assert_select '.wm-moderation-reasons', text: /サークル名・詳細情報にひらがな・カタカナ/
      assert_includes response.body, '判定時の理由を保存'
    end
    get circle_blog_path(@circle, blog)
    assert_response :success
    assert_select '.wm-moderation-reasons', text: /外部リンクが2件以上/
    assert_select '.wm-moderation-reasons', text: /サークル名・詳細情報/
    assert_equal before, [blog.reload.moderation_status, @circle.reload.moderation_status]
    patch super_admin_blog_moderation_path(blog), params: { moderation_status: 'clear' }
    assert_equal 'clear', blog.reload.moderation_status
    assert_equal ['foreign_links'], blog.moderation_reasons.map { |r| r['code'] }
    get circle_blog_path(@circle, blog)
    assert_select '.wm-moderation-reasons h4', text: /過去の判定理由/
  end

  test 'legacy decisions are labelled as reference information and unknown stops are explicit' do
    @circle.blogs.create!(title: '報告1', content: @content)
    @circle.blogs.create!(title: '報告2', content: @content)
    old = @circle.blogs.create!(title: '報告3', content: @content)
    old.update_columns(moderation_reasons: [], moderation_checked_at: nil)
    login_master
    [super_admin_circles_path, circle_blog_path(@circle, old)].each do |path|
      get path
      assert_response :success
      assert_select '.wm-moderation-reasons', text: /当時の判定理由は未保存/
      assert_select '.wm-moderation-reasons', text: /同じ本文のブログが2件以上/
    end
    assert_empty old.reload.moderation_reasons
    assert_nil old.moderation_checked_at
    old.update_columns(content: @content + '独自の内容に変更しました。', created_at: 2.hours.ago)
    get circle_blog_path(@circle, old)
    assert_select '.wm-moderation-reasons', text: /現在のデータでは該当条件を確認できません/
    old.update_column(:moderation_status, 'blocked')
    get circle_blog_path(@circle, old)
    assert_select '.wm-moderation-reasons', text: /具体的な停止理由は記録されていません/
  end

  test 'reasons are escaped and shown only to master on circle and blog pages' do
    blog = @circle.blogs.create!(title: 'Weekly report', content: 'Read https://one.example.test and https://two.example.test ' * 5)
    blog.update_column(:moderation_reasons, [{ 'code' => 'foreign_links', 'message' => '<img src=x onerror=alert(1)>' }])
    login_master
    get circle_blog_path(@circle, blog)
    assert_select '.wm-moderation-reasons img', count: 0
    assert_select '.wm-moderation-reasons [onerror]', count: 0
    assert_includes response.body, '&lt;img'
    delete destroy_webmaster_session_path
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    get circle_blog_path(@circle, blog)
    assert_response :success
    assert_select '.wm-moderation-reasons', count: 0
    get super_admin_circles_path
    assert_redirected_to new_webmaster_session_path
    delete destroy_admin_user_session_path
    assert_raises(ActiveRecord::RecordNotFound) { get circle_blog_path(@circle, blog) }
  end

  private
  def login_master
    post webmaster_session_path, params: { webmaster: { email: @master.email, password: 'test-password-123' } }
  end
end
