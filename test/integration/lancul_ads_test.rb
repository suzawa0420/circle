require 'test_helper'
require_relative '../support/chat_records'

class LanculAdsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    @english = Event.create!(name: '英会話', ruby: 'english', category: @circle.category, order: '2')
  end

  test 'English circle search shows one ad after two results or the last short result' do
    get event_path(@circle.event.ruby)
    assert_select '.affiliate-ad', count: 0
    @circle.update!(event: @english)
    get event_path('english')
    assert_ad 'search'
    assert_select '.circle-results-grid > li:nth-child(2).affiliate-ad-slot', count: 1
    9.times do |i|
      copy = @circle.dup
      copy.assign_attributes(name: "英会話サークル#{i}", unique_id: nil)
      copy.save!
    end
    get event_prefecture_path('english', @circle.prefecture.kana)
    assert_ad 'search'
    assert_select '.circle-results-grid > li:nth-child(3).affiliate-ad-slot', count: 1
    assert_select '.circle-results-grid > .user_item_wrap', count: 10
    assert_select '.circle-results-grid > .list_ad', count: 0
    get circles_path
    assert_select '.affiliate-ad', count: 0
  end

  test 'empty searches require an explicit English event and never infer it from keywords' do
    get circles_search_index_path, params: { detailed: '1', event_id: @english.id, q: '該当なしのサークル' }
    assert_response :success
    assert_ad 'search_empty'
    get circles_search_index_path, params: { detailed: '1', event_id: @circle.event_id, q: '該当なしのサークル' }
    assert_select '.affiliate-ad', count: 0
    get circles_search_index_path, params: { detailed: '1', q: '英会話該当なし' }
    assert_select '.affiliate-ad', count: 0
  end

  test 'English blog listings show one ad including empty results and short lists' do
    get blogs_event_path('english')
    assert_response :success
    assert_ad 'blog_search_empty'
    @circle.update!(event: @english)
    create_blog
    get blogs_event_path('english')
    assert_ad 'blog_search'
    9.times do |i|
      @circle.blogs.create!(title: "活動報告#{i}", content: "#{i}回目の英会話の活動で楽しく交流しました。" * 8)
    end
    get blogs_event_path('english')
    assert_select '.blog-results-grid > .users-form', count: 10
    assert_select '.blog-results-grid > div:nth-child(3).affiliate-ad-slot', count: 1
    assert_select '.blog-results-grid > .list_ad', count: 0
    get blogs_event_prefecture_path('english', @circle.prefecture.kana)
    assert_ad 'blog_search'
    get blogs_path
    assert_select '.affiliate-ad', count: 0
    @circle.update!(event: Event.find_by!(ruby: 'chat-basketball'))
    get blogs_event_path(@circle.event.ruby)
    assert_select '.affiliate-ad', count: 0
  end

  test 'circle blog archive and detail follow the circle genre' do
    blog = create_blog
    get circle_blogs_path(@circle)
    assert_select '.affiliate-ad', count: 0
    get circle_blog_path(@circle, blog)
    assert_select '.affiliate-ad', count: 0
    @circle.update!(event: @english)
    get circle_blogs_path(@circle)
    assert_ad 'circle_blogs'
    get circle_blog_path(@circle, blog)
    assert_ad 'circle_blog'
    get circle_path(@circle)
    assert_select '.affiliate-ad', count: 0
  end

  test 'upcoming events insert one ad after two results across date groups and on every page' do
    @circle.update!(event: @english)
    21.times do |i|
      @circle.schedules.create!(day: (Date.current + i).iso8601, title: "英会話イベント#{i}", venue: 'カフェ')
    end
    get '/dates/english'
    assert_ad 'event_search'
    assert_select '.event-results__card', count: 20
    assert_equal %w[event event ad], event_result_order.first(3)
    assert_select 'h1', text: /全21件/
    get "/dates/english/#{@circle.prefecture.kana}", params: { page: 2 }
    assert_ad 'event_search'
    assert_equal %w[event ad], event_result_order
    get dates_path
    assert_select '.affiliate-ad', count: 0
    get "/dates/#{Event.find_by!(ruby: 'chat-basketball').ruby}"
    assert_select '.affiliate-ad', count: 0
  end

  test 'day and period event searches keep all events and put the ad third' do
    @circle.update!(event: @english)
    4.times do |i|
      @circle.schedules.create!(day: Date.current.iso8601, title: "今日の英会話#{i}", venue: 'カフェ')
    end
    date_path = Date.current.strftime('%Y/%m/%d')
    ["/dates/english/#{date_path}", '/dates/english/today', '/dates/english/this_week',
     "/dates/english/#{@circle.prefecture.kana}/today"].each do |path|
      get path
      assert_ad 'event_search'
      assert_select '.event-results__card', count: 4
      assert_equal %w[event event ad event event], event_result_order
    end
    get dates_path, params: { event: 'english' }
    assert_response :moved_permanently
    follow_redirect!
    assert_ad 'event_search'
    assert_equal %w[event event ad], event_result_order.first(3)
  end

  test 'empty event searches show an ad only when its genre is selected' do
    ['/dates/english', '/dates/english/tomorrow',
     "/dates/english/#{@circle.prefecture.kana}/next_week"].each do |path|
      get path
      assert_ad 'event_search_empty'
      assert_select '.event-results__empty', count: 1
      assert_select '.event-results__card', count: 0
    end
    get dates_path
    assert_select '.affiliate-ad', count: 0
    get tomorrow_events_path
    assert_select '.affiliate-ad', count: 0
  end

  test 'participant ad follows current interests and does not appear in messages or public profiles' do
    post member_session_path, params: { member: { email: @member.email, password: 'test-password-123' } }
    get member_path(@member)
    assert_select '.affiliate-ad', count: 0
    @member.events << @english
    get member_path(@member)
    assert_ad 'participant_mypage'
    assert_includes response.headers['Cache-Control'], 'no-store'
    get conversations_path
    assert_select '.affiliate-ad', count: 0
    get member_profile_path(@member)
    assert_select '.affiliate-ad', count: 0
    @member.events.delete(@english)
    get member_path(@member)
    assert_select '.affiliate-ad', count: 0
  end

  test 'webmaster search cards omit edit and delete controls' do
    master = Webmaster.create!(id: 1, email: 'affiliate-webmaster@example.test', password: 'test-password-123')
    post webmaster_session_path, params: { webmaster: { email: master.email, password: 'test-password-123' } }
    @circle.update!(event: @english)
    get event_path('english')
    assert_ad 'search'
    assert_select '.circle-results-grid .moderator-edit-btn, .circle-results-grid .moderator-delete-btn', count: 0
    assert_select '.circle-results-grid a[data-method="delete"]', count: 0
    get edit_user_path(@circle)
    assert_response :success
  end

  test 'optimized public listing CSS retains the shared ad styles' do
    css = Rails.application.assets.find_asset('public_listing.css').to_s
    %w[.affiliate-ad .affiliate-ad__action .affiliate-ad__pixel .affiliate-ad-slot .affiliate-ad__banner].each do |selector|
      assert_includes css, selector
    end
  end

  private

  def event_result_order
    css_select('.event-results__list > li').map do |item|
      item.at_css('.affiliate-ad') ? 'ad' : 'event'
    end
  end

  def create_blog
    @circle.blogs.create!(title: '英会話の活動報告', content: 'みんなで日常の出来事を話しながら交流しました。' * 8)
  end

  def assert_ad(placement)
    assert_response :success
    assert_select '.affiliate-ad', count: 1
    assert_select ".affiliate-ad[data-affiliate-placement='#{placement}']", count: 1 do
      assert_select 'a[href="https://px.a8.net/svt/ejp?a8mat=4BELTL+Q75PM+4FL0+5YJRM"]', text: 'カフェ英会話を無料体験' do |links|
        assert_includes links.first['rel'].split, 'sponsored'
        assert_includes links.first['rel'].split, 'nofollow'
      end
      assert_select '.affiliate-ad__pr', text: '広告'
      assert_select '.affiliate-ad__disclosure', count: 0
      assert_select '.affiliate-ad__banner-link[href="https://px.a8.net/svt/ejp?a8mat=4BELTL+Q75PM+4FL0+614CX"] img[width="300"][height="250"][src^="https://www29.a8.net/svt/bgt?"]', count: 1
      assert_select 'img[width="1"][height="1"][src^="https://www19.a8.net/0.gif"]', count: 1
      assert_select 'img[width="1"][height="1"][src^="https://www14.a8.net/0.gif"]', count: 1
    end
  end
end
