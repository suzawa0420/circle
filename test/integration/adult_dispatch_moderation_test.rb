require 'test_helper'
require_relative '../support/chat_records'

class AdultDispatchModerationTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    @craft = Event.create!(name: '手芸・ハンドメイド', ruby: 'handicraft', category: @circle.category)
    @attributes = {
      name: '検証館｜【東京・大阪】高級出張', event: @craft,
      appeal: '東京・大阪対応の高級出張サービスです。厳選した日本人女性をご自宅やホテルまでお届けします。' \
              '安心してゆっくり楽しめる夜のひとときをお届けします。夜を一人で過ごしたくない方も、' \
              '素敵な女性との時間を楽しみたい方も、毎日100名以上の女性からお選びいただけます。' \
              'https://example.test/service'
    }
    @master = Webmaster.create!(id: 1, email: 'dispatch-review@example.test', password: 'test-password-123')
  end

  def login_master
    post webmaster_session_path, params: { webmaster: { email: @master.email, password: 'test-password-123' } }
  end

  test 'new dispatch promotion is held regardless of a hobby category and excluded publicly' do
    circle = @circle.dup
    circle.assign_attributes(@attributes)
    assert_no_difference 'ActionMailer::Base.deliveries.size' do
      circle.save!
    end
    assert_equal 'review', circle.moderation_status
    assert_equal [CircleProfilePolicy::DISGUISED_ADULT_SERVICE], circle.moderation_reasons.pluck('code')
    assert_equal CircleProfilePolicy.solicitation_fingerprint(circle), circle.moderation_reasons.first['fingerprint']
    refute circle.publicly_visible?
    assert_not_includes User.publicly_visible, circle
    assert_raises(ActiveRecord::RecordNotFound) { get circle_path(circle) }
    assert_raises(ActiveRecord::RecordNotFound) { get circle_blogs_path(circle) }
    schedule = circle.schedules.create!(title: '検証用日程', day: '2026-11-20', venue: '検証会場')
    assert_not_includes EventDayListing.public_schedules, schedule
    get circles_path
    assert_response :success
    assert_not_includes response.body, circle.name
  end

  test 'normalization and signals split across editable fields cannot bypass review' do
    @circle.assign_attributes(@attributes)
    variants = [
      { appeal: '手芸の集まりです。' + @attributes[:appeal] },
      { name: '高 級 出 張', appeal: @attributes[:appeal].gsub('女性', '女の子') },
      { name: "高級出\u200b張", appeal: @attributes[:appeal] },
      { name: '高級出張', appeal: @attributes[:appeal].gsub('お届け', 'おとどけ').gsub('100名', '１００名') },
      { name: '高級出張', appeal: @attributes[:appeal].gsub('女性', '女<b>性</b>').gsub('ホテル', 'ホテ&#12523;') },
      { name: '高級出張', appeal: "日本人女性をご自宅やホテルまで派遣します。", goal: '夜のひととき。女性からお選びください。', web: 'https://example.test/' }
    ]
    variants.each do |changes|
      candidate = @circle.dup
      candidate.assign_attributes(@attributes.merge(changes))
      assert CircleProfilePolicy.adult_dispatch_promotion?(candidate), changes.inspect
    end
    @circle.assign_attributes(@attributes.merge(appeal: @attributes[:appeal].sub('https://example.test/service', '')))
    refute CircleProfilePolicy.adult_dispatch_promotion?(@circle)
  end

  test 'ordinary premium travel mobile lessons women and hotels are not held by this rule' do
    examples = [
      ['東京・大阪の高級ホテル見学会', '女性も男性もホテルの建築や装飾を見学し、夜のひとときを楽しみます。'],
      ['女性向け出張手芸教室', '女性講師がご自宅やホテルへ出張し、手芸の初心者向け講座を開きます。'],
      ['出張サービスのある手芸教室', '女性向けに材料を自宅やホテルへお届けします。夜のひとときに作る作品をお選びください。'],
      ['女性カメラマンの出張撮影', 'ご自宅やホテルで女性カメラマンが撮影します。写真をお届けし、撮影プランを選べます。'],
      ['東京と大阪の女性交流会', '100名以上の女性との時間を楽しむ交流会です。ホテルの会場で一緒に手芸を楽しみます。']
    ]
    examples.each do |name, appeal|
      @circle.assign_attributes(name: name, appeal: appeal + 'https://example.test/', event: @craft)
      refute CircleProfilePolicy.adult_dispatch_promotion?(@circle), name
      @circle.save!
      assert_equal 'clear', @circle.reload.moderation_status, name
    end
  end

  test 'registration and later profile edits are held without rejecting or exposing their contents' do
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    assert_difference 'User.count', 1 do
      post users_path, params: { user: @attributes.except(:event).merge(event_id: @craft.id, prefecture_id: @circle.prefecture_id) }
    end
    assert_response :redirect
    assert_equal 'review', @owner.users.order(:id).last.moderation_status
    patch user_path(@circle), params: { user: @attributes.except(:event).merge(name: '編集後の高級出張サービス', event_id: @craft.id) }
    assert_response :redirect
    assert_equal 'review', @circle.reload.moderation_status
    patch super_admin_circle_moderation_path(@circle), params: { moderation_status: 'clear' }
    assert_equal 'review', @circle.reload.moderation_status
    get circle_path(@circle)
    assert_select 'button', text: '運営確認待ちにする', count: 0
  end

  test 'manual review affects one circle and records its current reasons without stopping the owner' do
    @circle.update_columns(@attributes.except(:event).merge(event_id: @craft.id)) # Existing unreviewed posting.
    sibling = @circle.dup
    sibling.assign_attributes(name: '通常の手芸サークル', appeal: '休日に手芸を楽しむサークルです。' * 10)
    sibling.save!
    get circle_path(@circle)
    assert_select 'button', text: '運営確認待ちにする', count: 0
    login_master
    get circle_path(@circle)
    assert_select 'button', text: '運営確認待ちにする', count: 0
    assert_not_includes response.body, 'このサークルだけを非公開にし、運営の確認待ち一覧へ移します。'
    assert_select "a[href='#{edit_user_path(@circle)}']"
    assert_select "a[href='#{user_path(@circle)}'][data-method=delete]"
    assert_no_difference 'ActionMailer::Base.deliveries.size' do
      patch super_admin_circle_moderation_path(@circle), params: { moderation_status: 'review' }
    end
    assert_redirected_to super_admin_circles_path
    assert_equal 'review', @circle.reload.moderation_status
    assert_equal [CircleProfilePolicy::DISGUISED_ADULT_SERVICE], @circle.moderation_reasons.pluck('code')
    refute @owner.reload.suspended?
    assert_equal 'clear', sibling.reload.moderation_status
    get super_admin_circles_path
    assert_select '.webmaster-card', text: /成人向けサービスの宣伝でないか運営確認が必要/
  end

  test 'approval requires the content actually reviewed and further edits return to the queue' do
    @circle.update!(@attributes)
    login_master
    fingerprint = CircleProfilePolicy.solicitation_fingerprint(@circle)
    get super_admin_circles_path
    assert_select "input[name=profile_fingerprint][value='#{fingerprint}']"
    @circle.update!(goal: '追加の案内です。')
    patch super_admin_circle_moderation_path(@circle), params: { moderation_status: 'clear', profile_fingerprint: fingerprint }
    assert_equal 'review', @circle.reload.moderation_status
    patch super_admin_circle_moderation_path(@circle), params: { moderation_status: 'clear', profile_fingerprint: CircleProfilePolicy.solicitation_fingerprint(@circle) }
    assert_equal 'clear', @circle.reload.moderation_status
    @circle.update!(switch: '受付終了')
    assert_equal 'clear', @circle.reload.moderation_status
    @circle.update!(goal: '宣伝文を変更しました。')
    assert_equal 'review', @circle.reload.moderation_status
    stale_editor = User.find(@circle.id)
    @circle.update_columns(moderation_status: 'blocked')
    stale_editor.update!(goal: 'さらに変更した案内です。')
    assert_equal 'blocked', @circle.reload.moderation_status
  end
end
