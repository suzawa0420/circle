require 'test_helper'
require_relative '../support/chat_records'

class DisguisedCircleSolicitationTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    travel_to Time.zone.local(2026, 10, 27, 12)
    create_chat_records
    @fishing = Event.create!(name: '釣り', ruby: 'fishing', category: @circle.category, order: '2')
    @attributes = {
      event: @fishing, name: '東京＆大阪｜大人の交流サークル', goal: '恋愛相手を探しています。参加者募集。',
      appeal: ('互いに寄り添いながら気軽に話せる相手を募集しています。' * 6) + 'Telegram: @example_only',
      contact: '', web: '', line_id: '', twitter: '', instagram: ''
    }
  end
  teardown { travel_back }

  test 'new disguised romantic solicitation is held before any public population or detail' do
    circle = @circle.dup
    circle.assign_attributes(@attributes)
    assert_no_difference 'ActionMailer::Base.deliveries.size' do
      circle.save!
    end
    assert_equal 'review', circle.moderation_status
    assert_equal [CircleProfilePolicy::DISGUISED_SOLICITATION], circle.moderation_reasons.pluck('code')
    assert_match(/\A[0-9a-f]{64}\z/, circle.moderation_reasons.first['fingerprint'])
    refute circle.publicly_visible?
    assert_not_includes User.publicly_visible, circle
    schedule = circle.schedules.create!(title: '検証用の日程', day: '2026-10-30', venue: '検証用の会場')
    assert_not_includes EventDayListing.public_schedules, schedule
    assert_empty EventDaySitemap.each_path.to_a
    [circle_path(circle), user_schedules_path(circle), user_schedule_path(circle, schedule),
     circle_blogs_path(circle)].each do |path|
      assert_raises(ActiveRecord::RecordNotFound) { get path }
    end
    get ogp_user_schedule_path(circle, schedule, format: :png)
    assert_response :not_found
    [circles_path, circles_search_index_path(detailed: '1', q: '大人の交流')].each do |path|
      get path
      assert_response :success
      refute_includes response.body, circle.name
    end
    assert_raises(ActiveRecord::RecordNotFound) { get user_schedule_path(circle, schedule), as: :json }
  end

  test 'reported language and obfuscated destination variants are reviewed together' do
    ['Telegram：@example_only', 'T G：@example_only', 'Gle ezy：example_only', 'Discord：example_only',
     'https://example.test/invite'].each do |destination|
      @circle.assign_attributes(@attributes.merge(goal: '歡迎加入，尋找浪漫愛情。', appeal: "気軽に話せる方を募集しています。 #{destination}"))
      assert CircleProfilePolicy.disguised_solicitation?(@circle), destination
    end
  end

  test 'ordinary words language contacts and romantic study alone are not held by this rule' do
    cases = [
      { goal: '気軽に話せる参加者を募集しています。' },
      { goal: '恋愛相手について学びます。', appeal: '性と恋愛を学ぶ読書サークルです。Telegram: @example_only' },
      { appeal: '互いに寄り添いながら話せる相手を募集しています。' },
      { goal: '東京と大阪で大人の交流を楽しみましょう。' },
      { goal: '歡迎加入，大家一起交流。' },
      { appeal: '釣りを楽しんだ後に交流します。Telegram: @example_only' },
      { appeal: '一起釣魚，歡迎加入。Telegram: @example_only' }
    ]
    cases.each do |changes|
      candidate = @circle.dup
      candidate.assign_attributes(@attributes.merge(changes))
      refute CircleProfilePolicy.disguised_solicitation?(candidate), changes.inspect
    end
    social = Event.create!(name: '交流会・カフェ会', ruby: 'gathering', category: @circle.category, order: '3')
    @circle.assign_attributes(@attributes.merge(event: social))
    refute CircleProfilePolicy.disguised_solicitation?(@circle)
  end

  test 'a public circle changing content or category cannot bypass review' do
    @circle.update!(@attributes.merge(event: Event.create!(name: '街コン・オフ会', ruby: 'meet-up', category: @circle.category, order: '4')))
    assert_equal 'clear', @circle.moderation_status
    @circle.update!(event: @fishing)
    assert_equal 'review', @circle.reload.moderation_status
  end

  test 'webmaster can inspect approve reject and content changes require fresh approval' do
    @circle.update!(@attributes)
    @master = Webmaster.create!(id: 1, email: 'solicitation-master@example.test', password: 'test-password-123')
    post webmaster_session_path, params: { webmaster: { email: @master.email, password: 'test-password-123' } }
    get super_admin_circles_path
    assert_response :success
    assert_includes response.body, '募集目的とカテゴリの確認が必要'
    assert_select "form[action='#{super_admin_circle_moderation_path(@circle)}'] input[value='clear']"
    assert_select "form[action='#{super_admin_circle_moderation_path(@circle)}'] input[value='blocked']"
    displayed_fingerprint = CircleProfilePolicy.solicitation_fingerprint(@circle)
    assert_select "input[name='profile_fingerprint'][value='#{displayed_fingerprint}']"
    @circle.update!(appeal: @circle.appeal + '新しい説明です。')
    patch super_admin_circle_moderation_path(@circle), params: { moderation_status: 'clear', profile_fingerprint: displayed_fingerprint }
    assert_equal 'review', @circle.reload.moderation_status
    assert_match(/最新の内容/, flash[:alert])
    patch super_admin_circle_moderation_path(@circle), params: { moderation_status: 'clear' }
    assert_equal 'review', @circle.reload.moderation_status
    patch super_admin_circle_moderation_path(@circle), params: { moderation_status: 'clear', profile_fingerprint: CircleProfilePolicy.solicitation_fingerprint(@circle) }
    assert_equal 'clear', @circle.reload.moderation_status
    approved = @circle.moderation_reasons.first['fingerprint']
    assert_equal CircleProfilePolicy.solicitation_fingerprint(@circle), approved
    @circle.update!(appeal: @circle.appeal)
    @circle.update!(switch: '受付終了')
    assert_equal 'clear', @circle.reload.moderation_status
    @circle.update!(contact: 'Discord: changed_example')
    assert_equal 'review', @circle.reload.moderation_status
    refute_equal approved, @circle.moderation_reasons.first['fingerprint']
    patch super_admin_circle_moderation_path(@circle), params: { moderation_status: 'blocked' }
    @circle.update!(goal: '通常の募集に変更しました。')
    assert_equal 'blocked', @circle.reload.moderation_status
  end

  test 'organizer cannot approve their own held profile and normal approval behavior stays intact' do
    @circle.update!(@attributes)
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    patch super_admin_circle_moderation_path(@circle), params: { moderation_status: 'clear' }
    assert_equal 'review', @circle.reload.moderation_status
    assert_response :redirect
    @circle.update!(goal: '通常の活動です。', appeal: '釣りを楽しむ仲間を募集しています。')
    assert_equal 'review', @circle.reload.moderation_status
  end

  test 'pending edited names do not enter existing conversation notifications' do
    @circle.update!(@attributes)
    @conversation.reload.user = @circle
    @conversation.update!(review_deadline: 2.weeks.from_now)
    [ChatMailer.new_messages(@conversation, 'member'), ChatMailer.new_messages(@conversation, 'owner'),
     ChatMailer.review_received(@conversation, 'member')].each do |mail|
      refute_includes mail.subject, @circle.name
      refute_includes mail.body.decoded, @circle.name
      assert_includes mail.body.decoded, conversation_path(@conversation)
    end
    @circle.update_columns(moderation_status: 'clear')
    assert_includes ChatMailer.new_messages(@conversation, 'member').subject, @circle.name
  end
end
