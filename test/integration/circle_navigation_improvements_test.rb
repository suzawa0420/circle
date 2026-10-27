require 'test_helper'
require_relative '../support/chat_records'

class CircleNavigationImprovementsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords
  include Devise::Test::IntegrationHelpers

  setup do
    travel_to Time.zone.local(2026, 10, 27, 12)
    create_chat_records
  end
  teardown { travel_back }

  test 'next activity is near basic information and shares the filtered existing schedule list' do
    @circle.schedules.create!(day: '2026-10-26', venue: '過去の場所', title: '過去')
    @circle.schedules.create!(day: '2026-10-27', time_s: '09:00', time_e: '11:00', venue: '終了の場所', title: '終了')
    @circle.schedules.create!(day: '2026-10-28', venue: '中止の場所', title: '中止', recruitment: '中止')
    upcoming = @circle.schedules.create!(day: '2026-10-29', time_s: '09:00', venue: '公開の体育館',
      member_venue: '参加者限定の体育館', venue_address: '参加者限定住所', title: '朝の活動')
    @circle.schedules.create!(day: '2026-10-29', time_s: '18:00', venue: '夜の体育館', title: '夜の活動')
    get circle_path(@circle)
    assert_response :success
    assert_select '.content_02 + .circle-upcoming' do
      assert_select 'time[datetime=?]', upcoming.day
      assert_select 'p', text: /10月29日.*09:00.*公開の体育館/m
      assert_select 'a[href=?]', user_schedules_path(@circle)
    end
    %w[過去の場所 終了の場所 中止の場所 参加者限定の体育館 参加者限定住所].each { |text| refute_includes response.body, text }
  end

  test 'empty upcoming schedule is explicit and private circles cannot expose a date' do
    get circle_path(@circle)
    assert_select '.circle-upcoming p', text: '公開されている今後の活動予定はありません。'
    @circle.update_columns(publication_status: 'draft')
    assert_raises(ActiveRecord::RecordNotFound) { get circle_path(@circle) }
    sign_in @owner
    @circle.schedules.create!(day: '2026-10-28', venue: '非公開の場所', title: '準備中')
    get circle_path(@circle)
    assert_select '.circle-upcoming time', count: 0
    refute_includes response.body, '非公開の場所'
  end

  test 'three existing ranked related candidates follow the final inquiry with no duplicates or hidden circles' do
    candidates = 5.times.map do |i|
      circle = @circle.dup
      circle.assign_attributes(name: "関連候補#{i}", unique_id: nil, last_post: Time.current - i.hours)
      circle.save!
      circle
    end
    candidates[0].update_columns(publication_status: 'draft')
    candidates[1].update_columns(moderation_status: 'blocked')
    get circle_path(@circle)
    assert_select '.profile-content > .mobile-circle-contact + .circle-related-candidates' do
      assert_select 'a', count: 3
      assert_select 'a[href=?]', circle_path(@circle), count: 0
      assert_select 'a' do |links|
        assert_equal candidates.drop(2).map { |circle| circle_path(circle) }, links.map { |link| link['href'] }
      end
    end
    assert_select '.others-user', count: 1
    refute_includes response.body, candidates[0].name
    refute_includes response.body, candidates[1].name
  end

  test 'missing related candidates has an explicit empty state' do
    get circle_path(@circle)
    assert_select '.circle-related-empty', text: /ほかに見つかりません/
    assert_select '.circle-related-candidates a', count: 0
  end

  test 'other areas sports and closed recruitment cannot become related candidates' do
    other_area = Prefecture.create!(name: '神奈川県', kana: 'navigation-other-area')
    other_sport = Event.create!(name: '別の種目', ruby: 'navigation-other-sport', category: @circle.category)
    [{ prefecture: other_area }, { event: other_sport }, { switch: '募集終了' }].each_with_index do |attributes, index|
      candidate = @circle.dup
      candidate.assign_attributes(attributes.merge(name: "対象外候補#{index}", unique_id: nil))
      candidate.save!
    end
    get circle_path(@circle)
    assert_select '.circle-related-candidates a', count: 0
    assert_select '.circle-related-empty', count: 1
  end
end
