require 'test_helper'
require_relative '../support/chat_records'

class DetailedCircleSearchTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    SearchResultCountCache::STORE.clear
    create_chat_records
    @beginner = Group.create!(name: '初心者')
    @experienced = Group.create!(name: '経験者')
    @twenties = Age.create!(name: '20代', decade: 20)
    @thirties = Age.create!(name: '30代', decade: 30)
    UsersGroup.create!(user: @circle, group: @beginner)
    UsersAge.create!(user: @circle, age: @twenties)
  end

  test 'regional search exposes collapsed detailed search with current area and event' do
    get event_prefecture_path(@circle.event.ruby, @circle.prefecture.kana)
    assert_response :success
    assert_select 'details.cb-detailed-search:not([open])'
    assert_select 'select[name=event_id] option[selected][value=?]', @circle.event.id.to_s
    assert_select 'select[name=prefecture_id] option[selected][value=?]', @circle.prefecture.id.to_s
    assert_select 'input[type=checkbox][name="group_ids[]"]', count: 2
    assert_select 'form.cb-circle-search-form', count: 1 do
      assert_select 'input[name=q]', count: 1
      assert_select 'select[name=event_id]', count: 1
      assert_select 'select[name=prefecture_id]', count: 1
      assert_select 'details form', count: 0
      assert_select 'details input[name=q], details select', count: 0
    end
  end

  test 'filters combine dimensions and retain selections without creating keyword records' do
    count = DbKeyword.count
    get circles_search_index_path, params: { detailed: '1', event_id: @circle.event.id, prefecture_id: @circle.prefecture.id,
      group_ids: [@beginner.id, @experienced.id], age_ids: [@twenties.id, @thirties.id], sort: '2' }
    assert_response :success
    assert_select 'h1', text: '全1件条件で絞り込んだサークル・チーム検索結果'
    assert_select 'details.cb-detailed-search[open]'
    assert_select 'input[name="group_ids[]"][checked]', count: 2
    assert_select 'input[name="age_ids[]"][checked]', count: 2
    assert_select 'nav.cb-sort a[href*="detailed=1"][href*="group_ids"]', count: 2
    assert_equal count, DbKeyword.count

    get circles_search_index_path, params: { detailed: '1', group_ids: [@experienced.id], age_ids: [@twenties.id] }
    assert_response :success
    assert_select 'h1', text: '全0件条件で絞り込んだサークル・チーム検索結果'
    assert_select 'details.cb-detailed-search[open]'
  end

  test 'keyword and visibility remain enforced and sub-prefecture matches' do
    other = Prefecture.create!(name: '神奈川県', kana: 'filter-kanagawa')
    @circle.update!(prefecture_sub: other)
    options = { detailed: '1', q: 'サークル', prefecture_id: other.id, group_ids: [@beginner.id] }
    get circles_search_index_path, params: options
    assert_response :success
    assert_select 'h1', text: '全1件「サークル」のサークル・チーム検索結果'
    get circles_search_index_path, params: options.merge(q: '見つからないキーワード')
    assert_select 'h1', text: '全0件「見つからないキーワード」のサークル・チーム検索結果'
    @circle.update_columns(publication_status: 'draft')
    SearchResultCountCache::STORE.clear
    get circles_search_index_path, params: options
    assert_select 'h1', text: '全0件「サークル」のサークル・チーム検索結果'
  end
end
