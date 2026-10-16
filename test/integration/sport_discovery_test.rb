require 'test_helper'
require_relative '../support/chat_records'

class SportDiscoveryTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    Rails.cache.clear
    SearchResultCountCache::STORE.clear
    create_chat_records
    @sport = Event.create!(name: '検証ピックルボール', ruby: 'test-pickleball', txt: 'ピックルボールサークル', category: @circle.category)
    @circle.update!(secondary_event_ids: [@sport.id], experience: '未経験可', equipment: 'パドル貸出あり', meeting_area: '駅前集合')
  end

  test 'secondary sport is discoverable through national regional and filtered listings without duplicates' do
    assert_equal [@circle.id], User.publicly_visible.event(Event.where(id: @sport.id)).pluck(:id)
    assert_equal [@circle.id], User.publicly_visible.event([@circle.event_id, @sport.id]).pluck(:id)
    assert_empty User.event(Event.none)
    group = Group.create!(name: '初心者')
    UsersGroup.create!(user: @circle, group: group)
    paths = [event_path(@sport.ruby), event_prefecture_path(@sport.ruby, @circle.prefecture.kana),
             CircleFilterLanding.path(event: @sport, prefecture: @circle.prefecture, group: group)]
    paths.each do |path|
      get path
      assert_response :success
      assert_select 'h1', text: /全1件/
      assert_select '.list_02', text: 'パドル貸出あり'
    end
    assert_includes CircleFilterLanding.each_populated_path.to_a, paths.last
    get circle_path(@circle)
    assert_select 'td', text: '駅前集合'
    assert_select 'a[href=?]', event_path(@sport.ruby), text: @sport.name
  end

  test 'draft circles stay hidden in secondary sports and sitemap combinations' do
    @circle.update_columns(publication_status: 'draft')
    get event_path(@sport.ruby)
    assert_select 'h1', text: /全0件/
    assert_select 'meta[name=robots][content*=noindex]'
    refute User.publicly_visible.for_event(@sport.id).exists?
  end

  test 'secondary sports also participate in event discovery and date sitemap' do
    today = Time.current.in_time_zone('Tokyo').to_date
    schedule = @circle.schedules.create!(day: today.iso8601, title: '体験会', venue: '公開体育館')
    assert_includes EventSearchPage.populations(today: today, event: @sport), [@sport.id, @circle.prefecture_id]
    assert_includes EventDaySitemap.each_path(today: today).to_a, EventSearchPage.path(event: @sport.ruby, date: today)
    assert EventDayListing.new(date: today, event: @sport).schedules.exists?(schedule.id)
    @circle.update_columns(publication_status: 'draft')
    assert_empty EventSearchPage.populations(today: today, event: @sport)
  end

  test 'owner can update details but cannot change existing secondary sports' do
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    patch user_path(@circle), params: { user: { secondary_event_ids: ['', @sport.id, @sport.id, @circle.event_id], equipment: '持参してください' } }
    assert_response :redirect
    assert_equal [@sport.id], @circle.reload.secondary_event_ids
    assert_equal '持参してください', @circle.equipment
    patch user_path(@circle), params: { user: { secondary_event_ids: [''] } }
    assert_equal [@sport.id], @circle.reload.secondary_event_ids
  end

  test 'invalid sports and overly long details are rejected' do
    @circle.secondary_event_ids = [2_000_000_000]
    refute @circle.valid?
    @circle.secondary_event_ids = []
    @circle.equipment = 'a' * 201
    refute @circle.valid?
  end

  test 'aliases find the intended sport without matching unnamed slugs' do
    @sport.update!(ruby: 'soft-tennis')
    assert_includes Event.matching_keyword('軟式テニス'), @sport
    assert_empty Event.matching_keyword('not-a-sport')
  end

  test 'reviewed classification preserves URLs publication and ranking and skips changed records' do
    require Rails.root.join('db/migrate/20261015020000_classify_reviewed_sports')
    previous = @circle.event_id
    snapshot = @circle.attributes.slice('publication_status', 'moderation_status', 'last_post', 'updated_at', 'cb_point')
    migration = ClassifyReviewedSports.new
    migration.define_singleton_method(:reviewed_rows) do
      [[@test_circle.id, @previous, @target.id, @target.category_id, 'チャット検証', false]]
    end
    migration.instance_variable_set(:@test_circle, @circle)
    migration.instance_variable_set(:@previous, previous)
    migration.instance_variable_set(:@target, @sport)
    ActiveRecord::Migration.suppress_messages { migration.up }
    assert_equal @sport.id, @circle.reload.event_id
    assert_equal [], @circle.secondary_event_ids
    assert_equal snapshot, @circle.attributes.slice(*snapshot.keys)
    assert_equal 1, @sport.reload.users_count
    assert_equal 0, Event.find(previous).users_count
    # Re-running after an owner changes classification must not override it.
    @circle.update_columns(event_id: previous, name: '別の活動に変更')
    ActiveRecord::Migration.suppress_messages { migration.up }
    assert_equal previous, @circle.reload.event_id
  end

  test 'classification suggestions exclude already assigned sports' do
    Event.where(ruby: 'pickleball').where.not(id: @sport.id).delete_all
    @sport.update!(ruby: 'pickleball')
    @circle.update!(name: 'ピックルボール体験会')
    refute_includes SportClassification.candidates('pickleball'), @circle
    @circle.update!(secondary_event_ids: [])
    assert_includes SportClassification.candidates('pickleball'), @circle
  end
end
