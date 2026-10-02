require 'test_helper'
require_relative '../support/chat_records'

class CircleLevelCardTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
  end

  test 'dashboard shows level progress and a review request destination' do
    @circle.update!(user_time: Time.current.to_s)
    @circle.schedules.create!(title: '週末の練習', venue: '体育館', day: (Date.current + 7).to_s)
    get "/users/#{@circle.id}/mypage"
    assert_response :success
    assert_select '.dashboard-stats', count: 0
    assert_select '.dashboard-level__value strong', text: '0'
    assert_select 'progress[value="10"]'
    assert_select '.dashboard-level__message', text: /あと0.9/
    assert_select ".dashboard-level a[href='#{user_reviews_path(@circle, anchor: 'review-request')}']", text: '口コミを依頼する'
    get user_reviews_path(@circle)
    assert_response :success
    assert_select '#review-request a', text: 'メッセージを開く'
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
