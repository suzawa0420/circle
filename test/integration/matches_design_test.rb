require 'test_helper'
require_relative '../support/chat_records'

class MatchesDesignTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    @circle.event.update!(matching: 1)
    @circle.update!(user_time: '2026-10-12 12:00:00 +0900')
    @match = Match.create!(id: @circle.id, user: @circle, recruit: '募集中', age_group: '20代中心', member: '男女混合', level: '中級', comment: '土曜日に練習試合を希望しています。')
  end

  test 'list and filtered pages retain search controls and actual update dates' do
    ['/matches', "/match/#{@circle.event.ruby}", "/match/prefectures/#{@circle.prefecture.kana}", "/match/#{@circle.event.ruby}/#{@circle.prefecture.kana}"].each do |path|
      get path
      assert_response :success
      assert_select 'h1', count: 1
      assert_select 'form[action="/matches"][method=get]' do
        assert_select 'select[name=event]'
        assert_select 'select[name=pref]'
        assert_select 'button[type=submit]', text: /この条件で探す/
        assert_select 'select[onchange]', count: 0
      end
      assert_select '.match-directory__card', count: 1
      assert_select '.match-directory__card a', href: match_path(@circle)
      assert_select '.match-directory__dates time', text: @match.updated_at.in_time_zone.strftime('更新 %Y年%-m月%-d日')
      assert_select '.match-directory__dates time', count: 1
    end
  end

  test 'design uses the real optional cover and keeps every card field' do
    @match.update_columns(updated_at: Time.zone.parse('2026-10-10 18:00:00'))
    upload = -> { Rack::Test::UploadedFile.new(Rails.root.join('public/images/default.png'), 'image/png') }
    @circle.update!(pic_header: upload.call, pic_profile: upload.call)
    header = @circle.reload.pic_header.identifier
    avatar = @circle.pic_profile.identifier
    get matches_path
    assert_response :success
    assert_select '.match-directory__card' do
      assert_select '.match-directory__card-link[href=?]', match_path(@circle), count: 1
      assert_select '.match-directory__card-top--cover' do
        assert_select 'img.match-directory__cover[data-original-src*=?][loading=lazy]', header, count: 1
        assert_select '.match-directory__status', text: '募集中', count: 1
        assert_select 'time.cb-listing-card__date[datetime="2026-10-12T12:00:00+09:00"]', text: '更新 2026年10月12日', count: 1
      end
      assert_select 'img.match-directory__avatar[src*=?]', avatar, count: 1
      assert_select '.match-directory__identity h2', text: @circle.name
      assert_select '.match-directory__sport', text: @circle.event.name
      assert_select '.match-directory__location', text: /東京都/
      assert_select '.match-directory__facts dt', count: 3
      assert_select '.match-directory__facts dd', text: '20代中心'
      assert_select '.match-directory__facts dd', text: '男女混合'
      assert_select '.match-directory__facts dd', text: '中級'
      assert_select '.match-directory__excerpt', text: @match.comment
    end

    @circle.update!(remove_pic_header: true, remove_pic_profile: true)
    @match.update_columns(recruit: '募集終了', member: nil)
    get matches_path
    assert_response :success
    assert_select '.match-directory__card-top--cover, .match-directory__cover', count: 0
    assert_select '.match-directory__card-top time.cb-listing-card__date', count: 1
    assert_select '.match-directory__card-top .match-directory__status.is-closed', text: '募集終了'
    assert_select '.match-directory__identity .match-directory__avatar.circle-avatar--empty'
    assert_select '.match-directory__facts dd', text: '未設定'
  end

  test 'combined search uses existing canonical landing URLs and keeps both selections' do
    get matches_path, params: { event: @circle.event.ruby, pref: @circle.prefecture.kana }
    assert_redirected_to "/match/#{@circle.event.ruby}/#{@circle.prefecture.kana}"
    follow_redirect!
    assert_select '#match_event option[selected]', text: 'バスケ'
    assert_select '#match_pref option[selected]', text: '東京都'
    get matches_path, params: { event: @circle.event.ruby }
    assert_redirected_to "/match/#{@circle.event.ruby}"
    get matches_path, params: { pref: @circle.prefecture.kana }
    assert_redirected_to "/match/prefectures/#{@circle.prefecture.kana}"
    assert_raises(ActiveRecord::RecordNotFound) { get matches_path, params: { event: 'unknown' } }
  end

  test 'zero results still allow another search and unpublished circles stay hidden' do
    @circle.update!(appeal: nil)
    get "/match/#{@circle.event.ruby}/#{@circle.prefecture.kana}"
    assert_response :success
    assert_select '.match-directory__filters', count: 1
    assert_select '.match-directory__empty', count: 1
    assert_select '.match-directory__card', count: 0
    assert_raises(ActiveRecord::RecordNotFound) { get match_path(@circle) }
  end

  test 'detail shows recruitment content and correct contact entry and limits related circles' do
    8.times do |i|
      circle = User.create!(name: "関連チーム#{i}", admin_user: @owner, appeal: @circle.appeal, category: @circle.category, event: @circle.event, prefecture: @circle.prefecture, switch: '募集中')
      Match.create!(id: circle.id, user: circle, recruit: '募集中')
    end
    get match_path(@circle)
    assert_response :success
    assert_select 'h1', count: 1, text: @circle.name
    assert_select '.match-directory__description', text: /土曜日に練習試合/
    assert_select '.match-directory__contact a', href: new_user_user_contact_path(@circle, entry: '2')
    assert_select '.match-directory__related .match-directory__card', count: 6
    assert_select '.match-directory__edit', count: 0
    @match.update!(recruit: '募集終了', comment: '<script>alert(1)</script>')
    get match_path(@circle)
    assert_select '.match-directory__contact', text: /募集を終了/
    assert_select '.match-directory__contact a', href: matches_path
    assert_select '.match-directory__description script', count: 0
  end

  test 'listing pagination retains the ten item limit and fresh circle activity dates' do
    11.times do |i|
      circle = User.create!(name: "検索チーム#{i}", appeal: @circle.appeal, admin_user: @owner, category: @circle.category, event: @circle.event, prefecture: @circle.prefecture, switch: '募集中')
      Match.create!(id: circle.id, user: circle, recruit: '募集中')
    end
    get matches_path
    assert_select '.match-directory__card', count: 10
    assert_select '.pagination a', minimum: 1
    get matches_path, params: { page: 2 }
    assert_select '.match-directory__card', count: 2
    @match.update_columns(updated_at: Time.zone.parse('2026-10-11 18:00:00'))
    @circle.update!(user_time: '2026-10-13 09:30:00 +0900')
    get matches_path, params: { page: 2 }
    assert_select '.match-directory__dates time[datetime="2026-10-13T09:30:00+09:00"]'
  end


  test 'newest update is shown once and matches structured data on lists and detail' do
    @match.update_columns(updated_at: Time.zone.parse('2026-10-10 18:00:00'))
    get matches_path
    assert_select '.match-directory__dates', text: /更新 2026年10月12日/, count: 1
    assert_select '.match-directory__dates time', count: 1
    assert_select '.match-directory__dates time[datetime="2026-10-12T12:00:00+09:00"]', text: '更新 2026年10月12日'
    list = structured_data_of_type('ItemList')
    assert_equal 'ItemList', list['@type']
    assert_equal 1, list['itemListElement'].first['position']
    assert_equal '2026-10-12T12:00:00+09:00', list['itemListElement'].first['item']['dateModified']
    [Time.zone.parse('2026-10-10 18:00:00'), Time.zone.parse('2026-10-13 09:45:00')].each do |updated_at|
      @match.update_columns(updated_at: updated_at)
      get match_path(@circle)
      data = structured_data_of_type('WebPage')
      expected = [updated_at, Time.zone.parse(@circle.user_time)].max.in_time_zone
      assert_equal 'WebPage', data['@type']
      assert_equal "https://circle-book.com/matches/#{@circle.id}", data['url']
      assert_equal expected.iso8601, data['dateModified']
      assert_select '.match-directory__profile .match-directory__dates time', count: 1
      assert_select ".match-directory__profile time[datetime='#{expected.iso8601}']", text: expected.strftime('%Y/%m/%d')
      refute_includes response.body, '募集更新：'
      refute_includes response.body, 'サークル更新：'
    end
  end

  test 'same-day timezone differences compare instants and missing or invalid circle dates fall back' do
    @match.update_columns(updated_at: Time.zone.parse('2026-10-12 12:00:00 +0900'))
    ['2026-10-12T04:00:00Z', nil, 'invalid date'].each do |circle_time|
      @circle.update!(user_time: circle_time)
      get match_path(@circle)
      data = structured_data_of_type('WebPage')
      expected = circle_time == '2026-10-12T04:00:00Z' ? '2026-10-12T13:00:00+09:00' : '2026-10-12T12:00:00+09:00'
      assert_equal expected, data['dateModified']
      assert_select ".match-directory__profile time[datetime='#{expected}']", count: 1
    end
  end

  test 'structured data escapes user names without creating script elements' do
    @circle.update!(name: 'テスト</script><script>alert(1)</script>')
    get match_path(@circle)
    data = structured_data_of_type('WebPage')
    assert_equal "#{@circle.name}の対戦相手・練習試合の募集", data['name']
    refute_includes response.body, '</script><script>alert(1)'
  end

  test 'owner editing remains available and legacy empty fields are supported' do
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    @circle.update!(user_time: 'invalid date')
    @match.update!(comment: nil, member: nil)
    get match_path(@circle)
    assert_response :success
    assert_select '.match-directory__edit', href: edit_match_path(@match)
    assert_select '.match-directory__dates time', count: 1
    assert_select '.match-directory__conditions dd', text: '未設定', count: 1
  end

  private

  def structured_data_of_type(type)
    data = css_select('script[type="application/ld+json"]').map { |node| JSON.parse(node.text) }.find { |item| item['@type'] == type }
    assert data, "Missing #{type} structured data"
    data
  end
end
