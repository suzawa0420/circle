require 'test_helper'
require_relative '../support/chat_records'

class CircleSearchExperienceTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords
  include Devise::Test::IntegrationHelpers

  setup do
    create_chat_records
    SearchResultCountCache::STORE.clear
    @beginner = Group.create!(name: '初心者')
    @experienced = Group.create!(name: '経験者')
    @age = Age.create!(name: '20代', decade: 20)
    UsersGroup.create!(user: @circle, group: @beginner)
    UsersAge.create!(user: @circle, age: @age)
  end

  test 'removing one filter retains all other dimensions and sort but resets pagination' do
    get circles_search_index_path, params: { detailed: '1', q: 'サークル', event_id: @circle.event_id,
      prefecture_id: @circle.prefecture_id, group_ids: [@beginner.id, @experienced.id], age_ids: [@age.id], sort: '2' }
    assert_response :success
    assert_select 'body[data-circle-search-list=true]'
    assert_select '.cb-active-filters__item', count: 6
    link = css_select('.cb-active-filters__item').find { |node| node['aria-label'] == '経験者の条件を外す' }
    query = Rack::Utils.parse_nested_query(URI(link['href']).query)
    assert_equal [@beginner.id.to_s], query['group_ids']
    assert_equal [@age.id.to_s], query['age_ids']
    assert_equal @circle.prefecture_id.to_s, query['prefecture_id']
    assert_equal @circle.event_id.to_s, query['event_id']
    assert_equal 'サークル', query['q']
    assert_equal '2', query['sort']
    refute query.key?('page')
    get link['href']
    assert_response :success
    assert_select '.no-hit-message', count: 0
  end

  test 'zero results offer bounded links without executing speculative searches' do
    get circles_search_index_path, params: { detailed: '1', q: '見つからない単語', event_id: @circle.event_id,
      prefecture_id: @circle.prefecture_id, sort: '3' }
    assert_response :success
    assert_select '.cb-search-recovery__link', count: 3
    link = css_select('.cb-search-recovery__link').find { |node| node.text.include?('見つからない単語') }
    get link['href']
    follow_redirect! if response.redirect?
    assert_response :success
    assert_select '.no-hit-message', count: 0
    assert_select 'select[name=prefecture_id] option[selected][value=?]', @circle.prefecture_id.to_s
  end

  test 'zero-result recovery removes the entire OR dimension rather than narrowing selected choices' do
    get circles_search_index_path, params: { detailed: '1', q: '見つからない単語',
      group_ids: [@beginner.id, @experienced.id], age_ids: [@age.id], sort: '2' }
    assert_response :success
    assert_select '.cb-search-recovery__link', text: '募集内容を外して探す', count: 1
    link = css_select('.cb-search-recovery__link').find { |node| node.text == '募集内容を外して探す' }
    query = Rack::Utils.parse_nested_query(URI(link['href']).query)
    refute query.key?('group_ids')
    assert_equal [@age.id.to_s], query['age_ids']
    assert_equal '見つからない単語', query['q']
    assert_equal '2', query['sort']
    assert_select '.cb-active-filters__item[aria-label=?]', '初心者の条件を外す', count: 1
  end

  test 'canonical landing filters survive removal and search words are HTML escaped' do
    get CircleFilterLanding.path(event: @circle.event, prefecture: @circle.prefecture, group: @beginner, age: @age), params: { sort: '2' }
    assert_response :success
    assert_select '.cb-active-filters__item', count: 4
    link = css_select('.cb-active-filters__item').find { |node| node['aria-label'] == '20代の条件を外す' }
    query = Rack::Utils.parse_nested_query(URI(link['href']).query)
    assert_equal [@beginner.id.to_s], query['group_ids']
    assert_equal '2', query['sort']
    refute query.key?('age_ids')
    get circles_search_index_path, params: { detailed: '1', q: '<script>alert(1)</script>' }
    assert_select '.cb-active-filters script', count: 0
  end

  test 'guest detail uses optimized assets and native lazy gallery while member keeps bookmark dependencies' do
    get circle_path(@circle)
    assert_response :success
    assert_select 'script[src*="public_detail"][defer]', count: 1
    assert_select 'script[src*="application"], script[src*="lazysizes"], script[src*="swiper"]', count: 0
    assert_select 'link[href*="public_detail"]', count: 1
    assert_select 'img.header_imege[loading=eager][fetchpriority=high][width="960"][height="384"]', count: 1
    assert_select 'link[rel=preload][as=image]', count: 1
    assert_select 'a[data-circle-search-back=?]', @circle.id.to_s
    assert_select 'img[data-src]', count: 0
    sign_in @member
    get circle_path(@circle)
    assert_response :success
    assert_select 'script[src*="application"]', count: 1
    assert_select 'a[data-remote=true][href=?]', user_bookmarks_path(@circle), minimum: 1
  end
end
