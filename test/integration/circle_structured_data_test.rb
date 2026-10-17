require 'test_helper'
require_relative '../support/chat_records'

class CircleStructuredDataTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup { create_chat_records }

  test 'JSON-LD round trips backslashes newlines quotes and HTML in every text field' do
    text = "記号 \\_ \\( \\\"引用\\\"\n改行\r\n\t<&> </script><script id=unexpected>文字</script>\u2028\u2029"
    @circle.update_columns(name: text, cost: text, review_score: '4.5')
    @circle.prefecture.update_columns(name: text)
    @circle.event.update_columns(txt: text)
    @member.update_columns(nickname: text)
    @circle.reviews.create!(member: @member, review: 1, comment: text)
    @circle.questions.create!(content: '参加できますか？', answer: text).update_columns(content: text)

    get circle_path(@circle)
    assert_response :success
    business = structured_data('Organization')
    assert_equal text, business['name']
    refute business.key?('priceRange')
    assert_equal "#{text}で活動している#{text}", business['description']
    assert_equal text, business['areaServed']['name']
    assert_equal text, business['review'].first['reviewBody']
    assert_equal text, business['review'].first['author']['name']
    faq = structured_data('FAQPage')
    assert_equal text, faq['mainEntity'].first['name']
    assert_equal text, faq['mainEntity'].first['acceptedAnswer']['text']
    assert_select 'script#unexpected', count: 0
    assert_select 'script[type="application/ld+json"]', count: 3
  end

  test 'optional rating and FAQ stay absent when there are no records' do
    get circle_path(@circle)
    assert_response :success
    business = structured_data('Organization')
    refute business.key?('aggregateRating')
    refute business.key?('review')
    refute structured_nodes.any? { |data| data['@type'] == 'FAQPage' }
    refute business.key?('image')
    refute business.key?('priceRange')
    assert_equal "https://circle-book.com#{circle_path(@circle)}#organization", business['@id']
  end

  test 'ratings retain total counts while examples match visible reviews and only real answers' do
    @circle.update_columns(review_score: '4')
    6.times do |i|
      @circle.reviews.create!(review: 1, comment: "楽しく参加しました#{i}")
      @circle.questions.create!(content: "参加についての質問#{i}", answer: i.zero? ? 'はい、参加できます。' : nil)
    end
    get circle_path(@circle)
    assert_response :success
    business = structured_data('Organization')
    assert_equal 6, business['aggregateRating']['reviewCount']
    assert_equal 4.0, business['aggregateRating']['ratingValue']
    assert_equal 3, business['review'].size
    assert_equal 3, css_select('.review_contents[id]').length
    assert_equal 1, business['review'].first['reviewRating']['bestRating']
    assert_equal 'ゲストユーザー', business['review'].first['author']['name']
    faq = structured_data('FAQPage')
    assert_equal 1, faq['mainEntity'].size
    assert_equal 'はい、参加できます。', faq['mainEntity'].first['acceptedAnswer']['text']
  end

  test 'circle ratings declare the real zero to five scale including fractional ratings below one' do
    @circle.reviews.create!(review: 0, comment: '今回は合いませんでした。')
    [0, 0.5, 5].each do |score|
      @circle.update_columns(review_score: score.to_s)
      get circle_path(@circle)
      assert_response :success
      rating = structured_data('Organization')['aggregateRating']
      assert_equal score, rating['ratingValue']
      assert_equal 0, rating['worstRating']
      assert_equal 5, rating['bestRating']
      assert_equal 1, rating['reviewCount']
    end
  end

  test 'missing or corrupt circle scores do not create fabricated or out of range ratings' do
    @circle.reviews.create!(review: 1, comment: '楽しく参加できました。')
    [nil, '', '-1', '5.1', 'unknown'].each do |score|
      @circle.update_columns(review_score: score)
      get circle_path(@circle)
      assert_response :success
      refute structured_data('Organization').key?('aggregateRating')
    end
  end

  private

  def structured_nodes
    css_select('script[type="application/ld+json"]').map { |node| JSON.parse(node.text) }
  end

  def structured_data(type)
    structured_nodes.find { |data| data['@type'] == type }.tap { |data| assert data, "Missing #{type}" }
  end
end
