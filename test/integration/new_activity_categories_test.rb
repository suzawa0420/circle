require 'test_helper'
require_relative '../support/chat_records'
require_relative '../../db/migrate/20261015030000_add_karate_handicraft_karaoke'

class NewActivityCategoriesTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    Rails.cache.clear
    SearchResultCountCache::STORE.clear
    create_chat_records
    Event.where(id: [62, 63, 64]).delete_all
    { 3 => 'その他のスポーツ', 12 => '趣味', 9 => '音楽・演劇' }.each do |id, name|
      Category.find_or_create_by!(id: id) { |category| category.name = name }
    end
  end

  test 'new categories support discovery images profile selection and secondary activities' do
    original = @circle.attributes.slice('event_id', 'category_id', 'updated_at', 'last_post')
    ActiveRecord::Migration.suppress_messages { AddKarateHandicraftKaraoke.new.up }
    assert_equal original, @circle.reload.attributes.slice(*original.keys)

    { 62 => ['karate', '空手', 3], 63 => ['handicraft', '手芸・ハンドメイド', 12],
      64 => ['karaoke', 'カラオケ', 9] }.each do |id, (slug, name, category_id)|
      event = Event.find(id)
      assert_equal [slug, name, category_id.to_s], [event.ruby, event.name, event.category_id]
      @circle.update!(event: event, category: event.category, secondary_event_ids: [])
      SearchResultCountCache::STORE.clear
      get event_path(slug)
      assert_response :success
      assert_select 'h1', text: /全1件#{Regexp.escape(name)}サークル募集/
      assert_select 'img[src=?]', "/images/events/#{slug}.jpg"
      assert_select 'meta[property="og:image"][content$=?]', "/images/events/#{slug}.jpg"
      assert File.file?(Rails.root.join("public/images/events/#{slug}.jpg"))
      assert_includes Event.matching_keyword(name), event
      assert_includes SportDiscoveryHelper::SPORT_GUIDES.keys, slug
    end

    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    get edit_user_path(@circle)
    assert_response :success
    assert_select 'select[name="user[secondary_event_ids][]"]', count: 0
    assert_select 'select[name="user[event_id]"] option[value="64"]', text: 'カラオケ'
    patch user_path(@circle), params: { user: { secondary_event_ids: ['', 63] } }
    assert_response :redirect
    assert_equal [], @circle.reload.secondary_event_ids
    refute_includes User.publicly_visible.for_event(63), @circle
  end

  test 'migration refuses existing IDs instead of overwriting another activity' do
    Event.create!(id: 62, category_id: 3, name: '既存種目', ruby: 'existing-activity')
    assert_raises(RuntimeError) do
      ActiveRecord::Migration.suppress_messages { AddKarateHandicraftKaraoke.new.up }
    end
    assert_equal 'existing-activity', Event.find(62).ruby
  end
end
