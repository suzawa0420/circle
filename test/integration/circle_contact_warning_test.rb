require 'test_helper'
require_relative '../support/chat_records'

class CircleContactWarningTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup { create_chat_records }

  test 'unflagged circles keep the normal inquiry links without a warning dialog' do
    get circle_path(@circle)
    assert_response :success
    assert_select '#circle-contact-warning', count: 0
    assert_select 'a[data-circle-contact-warning]', count: 0
    assert_select "a[href='#{new_user_conversation_path(@circle)}']", minimum: 1
    assert_select 'a[data-circle-inquiry-click]', count: 2
  end

  test 'network business flag adds one dialog shared by both detail inquiry buttons' do
    @owner.update!(check: 1)
    get circle_path(@circle)
    assert_response :success
    assert_select '#circle-contact-warning', count: 1
    assert_select 'a[data-circle-contact-warning][aria-haspopup=dialog]', count: 2
    assert_select 'a[data-circle-contact-warning][data-circle-inquiry-click]', count: 2
    assert_select 'a[data-contact-warning-continue][data-circle-inquiry-click]', count: 0
    assert_select '#circle-contact-warning-title', text: '勧誘目的の可能性があります'
    assert_select '#circle-contact-warning-description', text: /ネットワークビジネス（マルチ商法）/
    assert_select 'button[data-contact-warning-close][autofocus]', text: '問い合わせをやめる'
    assert_select "a[data-contact-warning-continue][href='#{new_user_conversation_path(@circle)}']"
  end

  test 'religious flag uses the religious warning and also protects the review inquiry link' do
    @owner.update!(check: 2)
    get user_reviews_path(@circle)
    assert_response :success
    assert_select 'a[data-circle-contact-warning]', minimum: 1
    assert_select 'a[data-circle-contact-warning][data-circle-inquiry-click]', minimum: 1
    assert_select '#circle-contact-warning-description', text: /宗教への勧誘/
    assert_select '#circle-contact-warning-description', text: /ネットワークビジネス/, count: 0
  end
end
