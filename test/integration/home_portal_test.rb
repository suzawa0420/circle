require 'test_helper'
require_relative '../support/chat_records'

class HomePortalTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    travel_to Time.zone.local(2026, 10, 14, 12)
    create_chat_records
  end
  teardown { travel_back }

  test 'five services show bounded public previews with working detail and directory links' do
    @circle.update!(recruitment: '初心者歓迎、一緒に活動しましょう')
    7.times do |index|
      @circle.schedules.create!(day: Date.current.iso8601, title: "今日のバスケ#{index}", venue: '公開体育館', time_s: '18:00', time_e: '20:00', recruitment: '募集中')
      Blog.insert_all!([{ user_id: @circle.id, title: "練習ブログ#{index}", content: 'バスケを楽しみました', moderation_status: 'clear', image_01: 'sample.jpg', created_at: Time.current - index.days, updated_at: Time.current - index.days }])
      Match.create!(user: @circle, recruit: '募集中', level: '初級', updated_at: Time.current - index.days)
    end
    city = City.create!(name: '世田谷区', city_kana: 'setagaya', prefecture: @circle.prefecture)
    7.times { |index| Place.create!(name: "体育館#{index}", tag: '1', address: '世田谷区1-1', city: city, prefecture: @circle.prefecture, event_ids: [@circle.event_id]) }
    get root_path
    assert_response :success
    assert_select '.home-portal__section', count: 5
    assert_select '.home-service--circles[href="/circles"]', text: 'サークルを探す'
    %w[circles dates blogs matches places].each { |path| assert_select ".home-service[href='/#{path}']", count: 1 }
    assert_select ".home-service__arrow", count: 0
    { circles: 1, events: 5, blogs: 5, matches: 5, places: 6 }.each do |key, count|
      assert_select "#home-#{key} .home-portal__rail > li", count: count
    end
    ['/circles', '/dates', '/blogs', '/matches', '/places'].each { |path| assert_select ".home-portal__more[href='#{path}']", count: 1 }
    assert_select "#home-circles a[href='#{circle_path(@circle)}']"
    assert_select '#home-events .event-results__status.status-open', count: 5
    assert_select '#home-blogs h3', text: '練習ブログ0'
    assert_select '#home-places .home-place__link', count: 6
    assert_select '.home-portal .pagination, .home-portal .list_ad', count: 0

    @circle.update_columns(publication_status: 'draft')
    get root_path
    assert_response :success
    %w[circles events blogs matches].each { |key| assert_select "#home-#{key} .home-portal__item", count: 0 }
    assert_select '#home-events .home-portal__empty', text: /今日のイベントはまだありません/
    assert_select '#home-places .home-portal__item', count: 6
  end

  test 'circle previews match the popular list ordering and stop at five' do
    @circle.update_columns(last_post: Time.current)
    6.times do |index|
      User.create!(name: "週末サークル#{index}", appeal: @circle.appeal, category: @circle.category,
                   event: @circle.event, prefecture: @circle.prefecture, admin_user: @owner,
                   switch: '募集中', cb_point: index * 10, last_post: Time.current - (index + 1).hours)
    end
    expected = User.publicly_visible.sort_2.limit(5).map { |circle| circle_path(circle) }
    get root_path
    assert_response :success
    assert_equal expected, css_select('#home-circles .home-preview > a').map { |link| link['href'] }
  end

  test 'unapproved blogs closed matches and non-today events never appear in previews' do
    Blog.insert_all!([{ user_id: @circle.id, title: '審査中ブログ', content: '本文', moderation_status: 'review', created_at: Time.current, updated_at: Time.current }])
    Match.create!(user: @circle, recruit: '募集終了')
    @circle.schedules.create!(day: Date.tomorrow.iso8601, title: '明日だけのイベント', venue: '体育館')
    get root_path
    assert_response :success
    %w[events blogs matches].each { |key| assert_select "#home-#{key} .home-portal__item", count: 0 }
    assert_not_includes response.body, '審査中ブログ'
    assert_not_includes response.body, '明日だけのイベント'
  end

  test 'blog previews exclude imageless posts and use the first available uploaded image' do
    Blog.insert_all!([
      { user_id: @circle.id, title: '画像なし最新記事', content: '本文', image_01: '', image_02: nil, image_03: nil, image_04: nil, moderation_status: 'clear', created_at: Time.current, updated_at: Time.current },
      { user_id: @circle.id, title: '二枚目だけ画像あり', content: '本文', image_01: nil, image_02: 'second.jpg', image_03: nil, image_04: nil, moderation_status: 'clear', created_at: Time.current - 1.hour, updated_at: Time.current - 1.hour },
      { user_id: @circle.id, title: '一枚目画像あり', content: '本文', image_01: 'first.jpg', image_02: nil, image_03: nil, image_04: nil, moderation_status: 'clear', created_at: Time.current - 2.hours, updated_at: Time.current - 2.hours }
    ])
    with_image = Blog.find_by!(title: '二枚目だけ画像あり')
    with_image.image_02.store!(File.open(Rails.root.join('public/images/events/basketball.jpg')))
    with_image.update_column(:image_02, with_image.image_02.identifier)
    first_image = Blog.find_by!(title: '一枚目画像あり')
    first_image.image_01.store!(File.open(Rails.root.join('public/images/events/basketball.jpg')))
    first_image.update_column(:image_01, first_image.image_01.identifier)
    get root_path
    assert_response :success
    assert_equal ['二枚目だけ画像あり', '一枚目画像あり'], css_select('#home-blogs h3').map(&:text)
    assert_select '#home-blogs .content_image_one', count: 2
    assert_select '#home-blogs .content_image_one[src*="/image_02/"]', count: 1
    assert_select '#home-blogs .content_image_one[src*="/image_01/"]', count: 1
  end
end
