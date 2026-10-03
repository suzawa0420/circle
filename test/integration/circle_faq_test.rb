require 'test_helper'
require_relative '../support/chat_records'

class CircleFaqTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  test 'circle details show answered and unanswered questions as collapsed accessible rows' do
    create_chat_records
    @circle.questions.create!(content: '初心者も参加できますか？', answer: "はい、参加できます。\n持ち物は運動靴です。")
    @circle.questions.create!(content: '次回の集合場所は？', answer: nil)
    get circle_path(@circle)
    assert_response :success
    assert_select '.circle-faq__item', count: 2
    assert_select '.circle-faq__item[open]', count: 0
    assert_select '.circle-faq__question', text: /初心者も参加できますか/
    assert_select '.circle-faq__answer', text: /はい、参加できます/
    assert_select '.circle-faq__pending', text: 'まだ回答されていません。'
    assert_select '.user_qa_btn a[href=?]', user_questions_path(@circle)
    assert_select '.user_slide_qa', count: 0
  end
end
