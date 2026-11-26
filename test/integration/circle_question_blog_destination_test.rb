require 'test_helper'
require_relative '../support/chat_records'

class CircleQuestionBlogDestinationTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords
  include Devise::Test::IntegrationHelpers

  setup { create_chat_records }

  test 'public question opens from the listing with correct status, related links and inquiry source' do
    question = @circle.questions.create!(content: '初参加で持っていく物は何ですか？', answer: '運動靴をご持参ください。')
    other_question = @circle.questions.create!(content: '初心者でも参加できますか？')

    get user_questions_path(@circle)
    assert_response :success
    answer_path = user_question_path(@circle, question)
    assert_select 'a.cb-circle-questions__link[href=?]', answer_path
    get answer_path
    assert_response :success
    assert_select '.cb-destination.cb-question-detail h1', text: question.content
    assert_select '.cb-question-detail__status.is-answered', text: '回答済み'
    assert_select '#answer', text: /運動靴をご持参ください/
    assert_select '.cb-destination__back[href=?]', user_questions_path(@circle)
    assert_select '.cb-destination__lower a[href=?]', user_question_path(@circle, other_question)
    assert_select '.cb-destination__side a[data-circle-inquiry-click]', count: 1
    assert_select '#question-answer', count: 0

    get user_question_path(@circle, other_question)
    assert_response :success
    assert_select '.cb-destination__main .cb-question-detail__status', text: '未回答'
    assert_select '#answer', text: /しばらくお待ちください/
    @circle.update_columns(switch: '募集終了')
    get user_question_path(@circle, other_question)
    assert_response :success
    assert_select '.cb-destination__side a[data-circle-inquiry-click]', count: 0
  end

  test 'blog opens from its index and renders article dates, photos and related posts' do
    earlier = @circle.blogs.create!(title: '前回の練習会', content: '和やかな雰囲気でバスケットボールをしました。' * 10)
    gallery = @circle.blogs.create!(title: '今月の試合を振り返りました', content: '試合に参加した皆さんとプレーを振り返りました。' * 10)
    @gallery = gallery
    example_image = Rails.root.join('public/images/events/basketball.jpg')
    File.open(example_image) { |file| gallery.image_01.store!(file) }
    gallery.update_columns(image_01: gallery.image_01.identifier, updated_at: gallery.created_at + 2.days)

    get circle_blogs_path(@circle)
    assert_response :success
    article_path = circle_blog_path(@circle, gallery)
    assert_select 'a.cb-circle-blogs__article-link[href=?]', article_path
    get article_path
    assert_response :success
    assert_select 'body.circle-destination-page.circle-scroll-header > .cb-blog-article-sentinel + .mobile-circle-summary', count: 1 do
      assert_select 'nav[aria-label="サークル内のページ"] [aria-current=page]', text: 'ブログ'
    end
    assert_select 'body > .mobile-circle-summary ~ .cb-destination-blog', count: 1
    assert_select '.cb-destination__context .mobile-circle-summary', count: 0
    assert_select '.cb-destination.cb-destination-blog h1', text: gallery.title
    assert_select '.cb-destination-blog__article p', text: /試合に参加/
    assert_select '.cb-destination-blog__dates time', count: 2
    assert_select '.cb-destination-blog__gallery', count: 0
    assert_select '.cb-destination-blog__photo', minimum: 1
    assert_select '.cb-destination__side a[data-circle-inquiry-click]', count: 1
    assert_select '.circle-blog-related__card[href=?]', circle_blog_path(@circle, earlier)

    File.open(example_image) { |file| gallery.image_02.store!(file) }
    gallery.update_columns(image_02: gallery.image_02.identifier)
    get article_path
    assert_response :success
    assert_select '.cb-destination-blog__gallery .swiper-slide', count: 2

    get circle_blog_path(@circle, earlier)
    assert_response :success
    assert_select '.cb-destination-blog__photo, .cb-destination-blog__gallery', count: 0
    assert_select '.cb-destination-blog__dates time', count: 1
  ensure
    @gallery&.image_01&.remove!
    @gallery&.image_02&.remove!
  end
end
