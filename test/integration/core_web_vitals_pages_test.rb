require 'test_helper'
require_relative '../support/chat_records'

class CoreWebVitalsPagesTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords
  include Devise::Test::IntegrationHelpers

  setup do
    SearchResultCountCache::STORE.clear
    create_chat_records
    @circle.update!(recruitment: '初心者歓迎')
    @city = City.create!(name: '世田谷区', city_kana: 'cwv-city', prefecture: @circle.prefecture)
    UsersCity.create!(user: @circle, city: @city)
    @station = Station.create!(name: '検証駅', city: @city)
  end

  test 'station listings preload the displayed image and keep results and filters' do
    base = "/#{@circle.prefecture.kana}/#{@city.city_kana}/#{@station.id}"
    ["/#{@circle.event.ruby}#{base}", "/prefectures#{base}"].each do |path|
      get path
      assert_response :success
      assert_lightweight_assets('public_listing')
      assert_select '.user_item_wrap', count: 1
      assert_select 'h1', text: /検証駅/
      image = css_select('img.header_imege_user_list[fetchpriority=high]').first
      assert_select 'link[rel=preload][as=image][href=?]', image['src'], count: 1
      assert_select 'form[action="/users/search"]', count: 1
    end
  end

  test 'empty station listing has no speculative image preload' do
    @circle.update_columns(publication_status: 'draft')
    get "/#{@circle.event.ruby}/#{@circle.prefecture.kana}/#{@city.city_kana}/#{@station.id}"
    assert_response :success
    assert_lightweight_assets('public_listing')
    assert_select 'link[rel=preload][as=image]', count: 0
    assert_select '.user_item_wrap', count: 0
  end

  test 'facility listings use deferred navigation without gallery or editor bundles' do
    ["/places", "/places/#{@circle.event.ruby}",
     "/places/#{@circle.event.ruby}/#{@circle.prefecture.kana}",
     "/places/#{@circle.event.ruby}/#{@circle.prefecture.kana}/#{@city.city_kana}"].each do |path|
      get path
      assert_response :success
      assert_lightweight_assets('public_directory')
      assert_select '.places-directory', count: 1
      assert_select 'link[rel=preload][as=image]', count: 0
    end
  end

  test 'public activity calendar retains its links without synchronous editor scripts' do
    get user_schedules_path(@circle)
    assert_response :success
    assert_lightweight_assets('public_directory')
    assert_select '.schedule-calendar__day', count: Date.current.end_of_month.day
    assert_select '.schedule-calendar__arrow[href*="month="]', count: 2
    assert_select '.mobile-circle-summary', count: 1
  end

  test 'signed in owners retain the management bundle on their calendar' do
    sign_in @owner
    get user_schedules_path(@circle)
    assert_response :success
    assert_select 'script[src*=application-]', count: 1
    assert_select 'link[rel=stylesheet][href*=public_directory]', count: 0
    assert_select 'a[href=?]', new_user_schedule_path(@circle), minimum: 1
  end

  test 'circle detail also uses responsive WebP branding' do
    get circle_path(@circle)
    assert_response :success
    assert_select '.mobile-site-heading source[type="image/webp"]', count: 1
    assert_select '.circle-desktop-toolbar source[type="image/webp"]', count: 1
  end

  private

  def assert_lightweight_assets(stylesheet)
    assert_select "link[rel=stylesheet][href*=#{stylesheet}]", count: 1
    assert_select 'script[src*=public_listing][defer]', count: 1
    assert_select 'script[src*=application-], script[src*=swiper], script[src*=lazysizes]', count: 0
    assert_select 'link[rel=stylesheet][href*=jquery-ui], link[rel=stylesheet][href*=photoswipe]', count: 0
    assert_select 'meta[name=listing-adsense]', count: 1
    assert_select 'script[src*=adsbygoogle]', count: 0
    assert_select '.circle-desktop-toolbar source[type="image/webp"]', count: 1
  end
end
