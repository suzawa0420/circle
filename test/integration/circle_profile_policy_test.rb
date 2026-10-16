require 'test_helper'
require_relative '../support/chat_records'
require_relative '../../db/migrate/20261016000000_review_late_night_relaxation_profiles'

class CircleProfilePolicyTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup { create_chat_records }

  test 'explicit sexual services are rejected across public profile fields' do
    CircleProfilePolicy::FIELDS.each do |field|
      circle = @circle.dup
      circle.public_send("#{field}=", 'デリヘルのご案内')
      refute circle.valid?, field
      assert circle.errors.of_kind?(field, :invalid), field
    end
    ['ﾃﾞﾘﾍﾙ', 'デ リ・ヘル', "デリ\u200bヘル", 'デリ<b>ヘル</b>',
     'デリ&#12504;ル', 'ＥＳＣＯＲＴ', 'デリバリーヘルス', '性服務', '外送茶'].each do |text|
      assert CircleProfilePolicy.prohibited?(text), text
    end
  end

  test 'the reported euphemistic profile is held and excluded from public listings' do
    @circle.assign_attributes(
      name: '東京・大阪自由行與夜間舒壓交流會',
      appeal: '初桜（はつざくら）です。東京・大阪の旅行や夜のイブニングガイド、ホテルライフスタイルについて紹介しています。' \
              '東京（新宿・池袋・六本木）や大阪（難波・心斎橋・梅田）へのお出かけ、プライベートなリフレッシュ時間をお手伝いします。' \
              '自由行與深夜舒壓諮詢交流： Telegram：@sample LINE ID：sample Gleezy：sample')
    @circle.save!
    assert_equal 'review', @circle.reload.moderation_status
    assert_equal ['adult_service_promotion'], @circle.moderation_reasons.pluck('code')
    refute @circle.publicly_visible?
    assert_not_includes User.publicly_visible, @circle
    assert_raises(ActiveRecord::RecordNotFound) { get circle_path(@circle) }
  end

  test 'the Chinese phrase is held even without external contacts and preserves blocked decisions' do
    @circle.update!(goal: '深夜舒壓のご案内')
    assert_equal 'review', @circle.reload.moderation_status
    @circle.update_columns(moderation_status: 'blocked')
    @circle.update!(contact: 'Telegram：@other LINE ID：other')
    assert_equal 'blocked', @circle.reload.moderation_status
  end

  test 'adding a sport detail alone rechecks moderation' do
    @circle.update!(goal: '舒壓のご案内', contact: 'Telegram：@sample LINE ID：sample')
    assert_equal 'clear', @circle.moderation_status
    @circle.update!(meeting_area: '深夜舒压のご案内')
    assert_equal 'review', @circle.reload.moderation_status
  end

  test 'phrase variations are held without external contacts' do
    ['深夜舒壓', '深夜舒压', '深 夜 舒・壓', '深夜舒<b>壓</b>', '深夜舒&#22739;'].each do |text|
      @circle.goal = text
      assert CircleProfilePolicy.review?(@circle), text
    end
  end

  test 'backfill changes only matching clear profiles and preserves existing decisions' do
    @circle.update_columns(goal: '深夜舒壓', moderation_status: 'clear')
    allowed = @circle.dup
    allowed.goal = '深夜のヨガでリフレッシュ'
    allowed.contact = 'Telegram：@sample LINE ID：sample Gleezy：sample'
    allowed.save!
    blocked = @circle.dup
    blocked.moderation_status = 'blocked'
    blocked.save!
    held = @circle.dup
    held.moderation_status = 'review'
    held.goal = '通常のサークル'
    held.save!
    held.update_columns(goal: '深夜舒压', moderation_reasons: [{ 'code' => 'manual', 'message' => '以前の理由' }])
    migration = ReviewLateNightRelaxationProfiles.new
    2.times { migration.up }
    assert_equal 'review', @circle.reload.moderation_status
    assert_equal ['adult_service_promotion'], @circle.moderation_reasons.pluck('code')
    assert_equal 'clear', allowed.reload.moderation_status
    assert_equal 'blocked', blocked.reload.moderation_status
    assert_equal ['manual'], held.reload.moderation_reasons.pluck('code')
  end

  test 'ordinary activities and external contacts alone remain allowed' do
    ['AV鑑賞', 'HEARTWAVE99', '夜のカフェ会', '夜間のヨガでリフレッシュ', '舒壓ヨガの交流会', '夜間舒壓交流會'].each do |name|
      @circle.update!(name: name, contact: 'Telegram：@sample LINE ID：sample')
      assert_equal 'clear', @circle.reload.moderation_status, name
    end
  end

  test 'owner cannot bypass validation by updating another profile field' do
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    patch user_path(@circle), params: { user: { area: 'デリ ヘル' } }
    assert_response :unprocessable_entity
    assert_equal '世田谷区', @circle.reload.area
  end

  test 'new registration cannot save a prohibited service' do
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    assert_no_difference('User.count') do
      post users_path, params: { user: { name: 'デリ・ヘルのご案内', event_id: @circle.event_id,
        prefecture_id: @circle.prefecture_id, appeal: @circle.appeal } }
    end
    assert_response :success
    assert_select '.form-error_message'
  end
end
