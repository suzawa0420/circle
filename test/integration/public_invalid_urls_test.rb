require 'test_helper'

class PublicInvalidUrlsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  test 'unknown public records and malformed dates return not found' do
    paths = %w[
      /blogs/events/null /blogs/events/null/prefectures/tokyo
      /blogs/events/basketball/prefectures/null
      /match/null /match/basketball/null /match/prefectures/null
      /categories/null /categories/null/tokyo /categories/prefectures/null
      /users/999999999/questions /users/999999999/question
      /dates/2026/9/null /dates/2026/2/30 /dates/2026/13/1
    ]
    paths.each do |path|
      assert_raises(ActiveRecord::RecordNotFound, path) { get path }
    end
  end

  test 'valid calendar date renders and invalid filters return not found' do
    get '/dates/2026/10/1'
    assert_response :success
    assert_raises(ActiveRecord::RecordNotFound) { get '/dates/2026/10/1', params: { event: 'null' } }
    assert_raises(ActiveRecord::RecordNotFound) { get '/dates/2026/10/1', params: { pref: 'null' } }
  end
end
