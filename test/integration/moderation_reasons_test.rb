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

  test 'only historical duplicate-only decisions are omitted from the master queue' do
    duplicate_only = @circle.blogs.create!(title: '重複理由のみ', content: @content)
    mixed = @circle.blogs.create!(title: 'Multiple review reasons', content: 'Read https://one.example.test and https://two.example.test ' * 5)
    blocked = @circle.blogs.create!(title: '運営による公開停止', content: @content + '停止対象です。')
    duplicate_reason = ModerationReasonReport.snapshot(['duplicate_content'])
    duplicate_only.update_columns(moderation_status: 'review', moderation_checked_at: Time.current, moderation_reasons: duplicate_reason)
    assert_equal "review", mixed.moderation_status
    mixed.update_column(:moderation_reasons, mixed.moderation_reasons + duplicate_reason)
    blocked.update_columns(moderation_status: 'blocked', moderation_checked_at: Time.current, moderation_reasons: duplicate_reason)

    login_master
    get super_admin_circles_path
    assert_response :success
    assert_select 'a', text: '重複理由のみ', count: 0
    assert_select 'a', text: 'Multiple review reasons'
    assert_select 'a', text: '運営による公開停止'
    assert_equal 'review', duplicate_only.reload.moderation_status
    assert_equal duplicate_reason, duplicate_only.moderation_reasons
    assert_equal 'blocked', blocked.reload.moderation_status
  end

  test 'consecutive distinct blogs remain public within the same hour' do
    freeze_time do
      6.times do |index|
        blog = @circle.blogs.create!(title: "活動報告#{index}", content: @content + "第#{index}回の活動です。")
        assert_equal 'clear', blog.reload.moderation_status
        assert blog.publicly_visible?
        assert_empty blog.moderation_reasons
      end
    end
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
    old = @circle.blogs.create!(title: 'Weekly report', content: 'Read https://one.example.test and https://two.example.test ' * 5)
    old.update_columns(moderation_reasons: [], moderation_checked_at: nil)
    login_master
    [super_admin_circles_path, circle_blog_path(@circle, old)].each do |path|
      get path
      assert_response :success
      assert_select '.wm-moderation-reasons', text: /当時の判定理由は未保存/
      assert_select '.wm-moderation-reasons', text: /外部リンクが2件以上/
    end
    assert_empty old.reload.moderation_reasons
    assert_nil old.moderation_checked_at
    old.update_columns(title: '活動報告', content: @content + '独自の内容に変更しました。', created_at: 2.hours.ago)
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

  test 'approved circle stays clear after repeated profile and publication changes' do
    @circle.update!(name: 'Outdoor Basketball', appeal: 'We play basketball every week. ' * 10)
    @circle.reload
    reasons = @circle.moderation_reasons
    checked_at = @circle.moderation_checked_at
    login_master
    patch super_admin_circle_moderation_path(@circle), params: { moderation_status: 'clear' }
    assert_redirected_to super_admin_circles_path

    [{ name: 'Outdoor Basketball Club' }, { appeal: 'Everyone is welcome. ' * 15 },
     { sport_details: { 'activity_style' => 'Basketball' } }, { appeal: 'Short description' },
     { appeal: 'We welcome new basketball players. ' * 10 }].each do |attributes|
      @circle.reload.update!(attributes)
      assert_equal 'clear', @circle.reload.moderation_status
    end
    assert_equal reasons, @circle.moderation_reasons
    assert_equal checked_at, @circle.moderation_checked_at
    get super_admin_circles_path
    assert_select 'a', text: 'Outdoor Basketball Club', count: 0
  end

  test 'existing clear decisions with saved reasons are respected' do
    @circle.update!(name: 'Outdoor Basketball', appeal: 'We play basketball every week. ' * 10)
    # This is how the approval endpoint stored decisions before this fix.
    @circle.update_column(:moderation_status, 'clear')
    @circle.reload.update!(appeal: 'New basketball players are welcome. ' * 10)
    assert_equal 'clear', @circle.reload.moderation_status
  end

  test 'approving a legacy circle remembers reasons even without saved evidence' do
    @circle.update!(name: 'Outdoor Basketball', appeal: 'We play basketball every week. ' * 10)
    @circle.update_columns(moderation_reasons: [], moderation_checked_at: nil)
    login_master
    patch super_admin_circle_moderation_path(@circle), params: { moderation_status: 'clear' }
    assert_equal ['non_japanese_profile'], @circle.reload.moderation_reasons.map { |r| r['code'] }
    assert @circle.moderation_checked_at
    @circle.update!(name: 'Outdoor Basketball Club')
    assert_equal 'clear', @circle.reload.moderation_status
  end

  test 'new concerns still flag an approved circle and blocked circles stay blocked' do
    @circle.update!(name: 'Outdoor Basketball', appeal: 'We play basketball every week. ' * 10)
    login_master
    patch super_admin_circle_moderation_path(@circle), params: { moderation_status: 'clear' }
    @circle.reload.update!(contact: '深夜舒壓')
    assert_equal 'review', @circle.reload.moderation_status
    assert_includes @circle.moderation_reasons.map { |r| r['code'] }, 'adult_service_promotion'
    patch super_admin_circle_moderation_path(@circle), params: { moderation_status: 'blocked' }
    @circle.reload.update!(name: 'Outdoor Basketball Club')
    assert_equal 'blocked', @circle.reload.moderation_status
  end

  private
  def login_master
    post webmaster_session_path, params: { webmaster: { email: @master.email, password: 'test-password-123' } }
  end
end
