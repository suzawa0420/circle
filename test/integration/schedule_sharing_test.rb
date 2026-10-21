require 'test_helper'
require_relative '../support/chat_records'

class ScheduleSharingTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    @schedule = @circle.schedules.create!(day: '2026-10-25', title: '初心者歓迎 & ボードゲーム',
      venue: '東京都新宿区', time_s: '16:30', time_e: '18:00', member_venue: 'メンバーだけの会場',
      venue_address: 'メンバーだけの住所', google_map: '限定地図の情報')
  end

  def sign_in_owner
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
  end

  def assert_public_share_content
    assert_select '[data-schedule-share]', count: 1
    assert_select 'textarea[data-share-text]' do |fields|
      text = fields.first.text
      assert_includes text, '初心者歓迎 & ボードゲーム'
      assert_includes text, '2026年10月25日（日）'
      assert_includes text, '16:30'
      assert_includes text, '18:00'
      assert_includes text, '東京都新宿区'
      refute_includes text, 'メンバーだけ'
      refute_includes text, '限定地図'
    end
    url = "https://circle-book.com#{user_schedule_path(@circle, @schedule)}"
    assert_select '[data-schedule-share][data-share-url=?]', url
    %w[x threads].each do |destination|
      link = css_select("a[data-share-destination='#{destination}']").sole
      uri = URI.parse(link['href'])
      assert_equal(destination == 'x' ? 'twitter.com' : 'www.threads.com', uri.host)
      query = URI.decode_www_form(uri.query).to_h
      assert_equal url, query['url']
      assert_includes query['text'], '初心者歓迎 & ボードゲーム'
      refute_includes query['text'], 'メンバーだけ'
      refute_includes link['href'], 'private-query'
      assert_equal '_blank', link['target']
      assert_includes link['rel'], 'noopener'
    end
    assert_select '[data-share-copy="post"]', text: /投稿文をコピー/
    assert_select '[data-share-copy="url"]', text: /URLをコピー/
    assert_select '[data-share-status][role="status"]'
    assert_select 'img.schedule-share__preview' do |images|
      assert_match %r{/users/#{@circle.id}/schedules/#{@schedule.id}/ogp.png\?v=[0-9a-f]{24}}, images.sole['src']
    end
  end

  test 'anonymous visitors get public editable sharing with both destination intents' do
    get user_schedule_path(@circle, @schedule), params: { source: 'private-query' }
    assert_response :success
    assert_select '#schedule-share:not([open])'
    assert_select '[data-share-heading]', text: '友だちにこのイベントを共有する'
    assert_public_share_content
    assert_not_includes response.body, 'メンバーだけ'
    assert_not_includes response.body, '限定地図'
  end

  test 'owners get organizer wording and the canonical public URL' do
    sign_in_owner
    get user_schedule_path(@circle, @schedule), params: { source: 'private-query' }
    assert_select 'summary [data-share-heading]', text: 'このイベントをSNSで知らせる'
    assert_public_share_content
  end

  test 'successful creation redirects to that event and offers sharing once above its details' do
    sign_in_owner
    post user_schedules_path(@circle), params: { schedule: { day: '2026-10-25', title: '作成したイベント', venue: '公開エリア' } }
    created = @circle.schedules.order(:id).last
    assert_redirected_to user_schedule_path(@circle, created)
    follow_redirect!
    assert_select '[data-share-created="true"][open]', count: 1
    assert_select 'summary [data-share-heading]', text: 'イベントを公開しました！'
    assert_select '#schedule-share + article.schedule-detail__card', count: 1
    assert_select '[data-share-dismiss]', text: 'あとで共有する'
    assert_select '[data-schedule-share-reopen]', count: 1
    get user_schedule_path(@circle, created)
    assert_select '[data-share-created="true"]', count: 0
    assert_select '#schedule-share:not([open])'
    assert_select '[data-share-dismiss]', count: 0
  end

  test 'failed creation preserves the form and never shows a published prompt' do
    sign_in_owner
    assert_no_difference 'Schedule.count' do
      post user_schedules_path(@circle), params: { schedule: { day: '', title: '入力中のイベント', venue: '' } }
    end
    assert_response :success
    assert_select '[data-schedule-share]', count: 0
    assert_select 'input[name="schedule[title]"][value="入力中のイベント"]'
  end

  test 'preparation follows successful sharing once and prefers the matching organizer guide' do
    organizer = Column.create!(title: 'バスケの備品', text: '備品を確認', publication_status: 'published', audience: 'organizer', event: @circle.event)
    participant = Column.create!(title: '参加の持ち物', text: '持ち物を確認', publication_status: 'published', audience: 'participant', event: @circle.event)
    Column.create!(title: '全種目の主催ガイド', text: '運営', publication_status: 'published', audience: 'organizer')
    sign_in_owner
    post user_schedules_path(@circle), params: { schedule: { day: '2026-10-25', title: '準備の確認', venue: '公開エリア' } }
    created = @circle.schedules.order(:id).last
    follow_redirect!
    assert_select '#schedule-share + .column-guide-links', count: 1
    assert_select '.column-guide-links__link', count: 2
    assert_select ".column-guide-links__link[href='#{column_path(organizer)}']"
    get user_schedule_path(@circle, created)
    assert_select '#schedule-share + .column-guide-links', count: 0
    assert_select ".column-guide-links__link[href='#{column_path(participant)}']"
    assert_select ".column-guide-links__link[href='#{column_path(organizer)}']", count: 0
  end

  test 'hidden circles and the member-only detail do not offer public sharing' do
    @circle.update!(unique_id: 'sharing-private-test', recruitment: '初心者歓迎')
    get "/schedules/#{@circle.unique_id}/#{@schedule.id}"
    assert_select '[data-schedule-share]', count: 0
    @circle.update_columns(moderation_status: 'held')
    sign_in_owner
    get user_schedule_path(@circle, @schedule)
    assert_select '[data-schedule-share]', count: 0
    post user_schedules_path(@circle), params: { schedule: { day: '2026-10-25', title: '非公開サークルの予定', venue: 'エリア' } }
    follow_redirect!
    assert_select '[data-schedule-share]', count: 0
    assert_not_includes response.body, 'イベントを公開しました！'
  end
end
