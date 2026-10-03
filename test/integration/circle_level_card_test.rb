require 'test_helper'
require_relative '../support/chat_records'

class CircleLevelCardTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
  end

  test 'dashboard shows level progress and prioritizes activity registration' do
    @circle.update!(user_time: Time.current.to_s)
    @circle.schedules.create!(title: '週末の練習', venue: '体育館', day: (Date.current + 7).to_s)
    get "/users/#{@circle.id}/mypage"
    assert_response :success
    assert_select '.dashboard-stats', count: 0
    assert_select '.dashboard-level__value strong', text: '0'
    assert_select 'progress[value="10"]'
    assert_select '.dashboard-level__message', text: /あと0.9/
    assert_select '.dashboard-level__ranking strong', text: /人気順で上位/
    assert_select '.dashboard-level__breakdown tbody tr', count: 5
    assert_select '.dashboard-level__breakdown th', text: 'メッセージ未返信'
    assert_select '.dashboard-level__guide', text: /旧お問い合わせは減点対象外/
    assert_select '.dashboard-level__breakdown tfoot td', text: '0.1'
    assert_select ".dashboard-level__actions a.dashboard-primary[href='#{new_user_schedule_path(@circle)}']", text: '活動日を追加'
    assert_select ".dashboard-level__actions a.dashboard-primary[href='#{new_circle_blog_path(@circle)}']", text: 'ブログを書く'
    assert_select '.dashboard-level__description', text: /まずは活動日を登録/
    assert_select '.dashboard-level__actions a', text: '口コミを依頼する', count: 0
    get user_reviews_path(@circle)
    assert_response :success
    assert_select '#review-request a', text: 'メッセージを開く'
  end

  test 'rival levels appear only on the owner dashboard and exclude owned or hidden circles' do
    other_owner = AdminUser.create!(email: 'rival-owner@example.test', password: 'test-password-123', email_verified_at: Time.current)
    rival = @circle.dup
    rival.assign_attributes(name: 'ライバルバスケ', admin_user: other_owner, cb_point: 7.4)
    rival.save!
    hidden = rival.dup
    hidden.assign_attributes(name: '非公開ライバル', moderation_status: 'blocked')
    hidden.save!
    get "/users/#{@circle.id}/mypage"
    assert_response :success
    assert_select '.dashboard-level__rival-name', text: rival.name
    assert_select '.dashboard-level__rival strong', text: 'Lv.7'
    assert_select '.dashboard-level__rival-name', text: @circle.name, count: 0
    assert_select '.dashboard-level__rival-name', text: hidden.name, count: 0
    get circles_path
    assert_select '.dashboard-level__rival', count: 0
  end

  test 'level card caps display and hides next level at maximum' do
    @circle.cb_point = 1000
    html = ApplicationController.render(partial: 'users/level_card', locals: { user: @circle })
    fragment = Nokogiri::HTML.fragment(html)
    assert_equal '100', fragment.at_css('.dashboard-level__value strong').text
    assert_equal 'MAX', fragment.at_css('.dashboard-level__badge').text
    assert_equal '100', fragment.at_css('progress')['value']
    refute_includes fragment.text, '次のレベルまで'
  end
end
