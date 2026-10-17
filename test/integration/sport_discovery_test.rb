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
    if User.connection.column_exists?(:users, :secondary_event_ids)
      User.connection.execute("UPDATE users SET secondary_event_ids = ARRAY[#{@sport.id}]::integer[] WHERE id = #{@circle.id}")
    end
    @circle.update!(experience: '未経験可', equipment: 'パドル貸出あり', meeting_area: '駅前集合')
  end

  test 'only primary sport is discoverable through national regional and filtered listings' do
    assert_empty User.publicly_visible.event(Event.where(id: @sport.id))
    assert_equal [@circle.id], User.publicly_visible.event([@circle.event_id, @sport.id]).pluck(:id)
    assert_empty User.event(Event.none)
    group = Group.create!(name: '初心者')
    UsersGroup.create!(user: @circle, group: group)
    paths = [event_path(@sport.ruby), event_prefecture_path(@sport.ruby, @circle.prefecture.kana),
             CircleFilterLanding.path(event: @sport, prefecture: @circle.prefecture, group: group)]
    paths.each do |path|
      get path
      assert_response :success
      assert_select 'h1', text: /全0件/
    end
    refute_includes CircleFilterLanding.each_populated_path.to_a, paths.last
    assert_includes CircleFilterLanding.each_populated_path.to_a, CircleFilterLanding.path(event: @circle.event, prefecture: @circle.prefecture, group: group)
    get event_path(@circle.event.ruby)
    assert_select 'h1', text: /全1件/
    assert_select '.list_02', text: 'パドル貸出あり'
    get circle_path(@circle)
    assert_select 'td', text: '駅前集合'
    assert_select 'a[href=?]', event_path(@sport.ruby), count: 0
    assert_select 'th', text: 'その他の活動種目', count: 0
    assert_not @circle.has_attribute?(:secondary_event_ids)
  end

  test 'draft circles stay hidden in secondary sports and sitemap combinations' do
    @circle.update_columns(publication_status: 'draft')
    get event_path(@sport.ruby)
    assert_select 'h1', text: /全0件/
    assert_select 'meta[name=robots][content*=noindex]'
    refute User.publicly_visible.for_event(@sport.id).exists?
  end

  test 'keyword and region discovery ignore retired secondary sport data' do
    get circles_search_index_path, params: { q: @sport.name }
    assert_response :success
    assert_select '.list_02', count: 0
    @sport.update!(ruby: 'pickleball')
    helper = Object.new.extend(SportDiscoveryHelper)
    refute_includes helper.region_discovery_sports(@circle.prefecture), @sport
    @circle.update!(event: @sport)
    assert_includes helper.region_discovery_sports(@circle.prefecture), @sport
  end

  test 'event discovery and date sitemap use primary sport and circle search use primary sport' do
    today = Time.current.in_time_zone('Tokyo').to_date
    schedule = @circle.schedules.create!(day: today.iso8601, title: '体験会', venue: '公開体育館')
    assert_empty EventSearchPage.populations(today: today, event: @sport)
    refute_includes EventDaySitemap.each_path(today: today).to_a, EventSearchPage.path(event: @sport.ruby, date: today)
    refute EventDayListing.new(date: today, event: @sport).schedules.exists?(schedule.id)
    refute User.publicly_visible.for_event(@sport.id).exists?(@circle.id)
    assert_includes EventSearchPage.populations(today: today, event: @circle.event), [@circle.event_id, @circle.prefecture_id]
    assert_includes EventDaySitemap.each_path(today: today).to_a, EventSearchPage.path(event: @circle.event.ruby, date: today)
    assert EventDayListing.new(date: today, event: @circle.event).schedules.exists?(schedule.id)
    @circle.update_columns(publication_status: 'draft')
    assert_empty EventSearchPage.populations(today: today, event: @circle.event)
  end

  test 'owner edit omits retired discovery fields and preserves existing data' do
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    get edit_user_path(@circle)
    assert_response :success
    assert_select 'summary', text: '種目ごとの参加条件・集合場所を入力する', count: 0
    SportDiscovery::DETAIL_FIELDS.each_key do |key|
      assert_select "input[name='user[#{key}]']", count: 0
    end
    assert_select 'input[name="user[area]"]', count: 1
    assert_select 'input[name="user[schedule]"]', count: 1
    patch user_path(@circle), params: { user: { secondary_event_ids: ['', @sport.id, @sport.id, @circle.event_id], equipment: '持参してください' } }
    assert_response :redirect
    assert_not @circle.reload.has_attribute?(:secondary_event_ids)
    assert_equal 'パドル貸出あり', @circle.equipment
    patch user_path(@circle), params: { user: { secondary_event_ids: [''] } }
    assert_not @circle.reload.has_attribute?(:secondary_event_ids)
  end

  test 'overly long details are rejected' do
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
    assert_includes SportClassification.candidates('pickleball'), @circle
    @circle.update!(event: @sport)
    refute_includes SportClassification.candidates('pickleball'), @circle
  end
end
