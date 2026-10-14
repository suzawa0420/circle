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
      assert_select '.match-directory__dates time', text: @match.updated_at.in_time_zone.strftime('%Y/%m/%d')
      assert_select '.match-directory__dates time', count: 1
    end
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
    assert_select '.match-directory__dates', text: /更新日：/, count: 1
    assert_select '.match-directory__dates time', count: 1
    assert_select '.match-directory__dates time[datetime="2026-10-12T12:00:00+09:00"]', text: '2026/10/12'
    list = JSON.parse(css_select('script[type="application/ld+json"]').last.text)
    assert_equal 'ItemList', list['@type']
    assert_equal 1, list['itemListElement'].first['position']
    assert_equal '2026-10-12T12:00:00+09:00', list['itemListElement'].first['item']['dateModified']
    [Time.zone.parse('2026-10-10 18:00:00'), Time.zone.parse('2026-10-13 09:45:00')].each do |updated_at|
      @match.update_columns(updated_at: updated_at)
      get match_path(@circle)
      data = JSON.parse(css_select('script[type="application/ld+json"]').last.text)
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
      data = JSON.parse(css_select('script[type="application/ld+json"]').last.text)
      expected = circle_time == '2026-10-12T04:00:00Z' ? '2026-10-12T13:00:00+09:00' : '2026-10-12T12:00:00+09:00'
      assert_equal expected, data['dateModified']
      assert_select ".match-directory__profile time[datetime='#{expected}']", count: 1
    end
  end

  test 'structured data escapes user names without creating script elements' do
    @circle.update!(name: 'テスト</script><script>alert(1)</script>')
    get match_path(@circle)
    data = JSON.parse(css_select('script[type="application/ld+json"]').last.text)
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
end
