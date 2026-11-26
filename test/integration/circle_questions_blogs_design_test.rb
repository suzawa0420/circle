require 'test_helper'
require_relative '../support/chat_records'

class CircleQuestionsBlogsDesignTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords
  include Devise::Test::IntegrationHelpers

  setup { create_chat_records }

  test 'Q and A keeps public question detail links and hides the form when acceptance is disabled' do
    answered = @circle.questions.create!(content: '初心者も参加できますか？', answer: 'もちろんです。')
    unanswered = @circle.questions.create!(content: '必要な持ち物は何ですか？')

    get user_questions_path(@circle)
    assert_response :success
    assert_select '.cb-public-circle--questions .cb-public-circle__main form[action=?]', user_questions_path(@circle) do
      assert_select 'textarea[name="question[content]"][aria-describedby="circle-question-rules"]'
      assert_select 'button[type="submit"][data-confirm]'
    end
    assert_select 'a[href=?] .cb-circle-questions__status', user_question_path(@circle, answered), text: '回答済み'
    assert_select 'a[href=?] .cb-circle-questions__status', user_question_path(@circle, unanswered), text: '未回答'
    assert_select '.cb-circle-questions__edit', count: 0

    @circle.update_columns(review_permit: false)
    get user_questions_path(@circle)
    assert_response :success
    assert_select '.cb-circle-questions__ask', count: 0
    assert_select 'a[href=?] .cb-circle-questions__status', user_question_path(@circle, answered), text: '回答済み'

    sign_in @owner
    get user_questions_path(@circle)
    assert_response :success
    assert_select 'a.cb-circle-questions__edit[href=?]', user_question_path(@circle, unanswered, anchor: 'question-answer')
    assert_select '.cb-circle-questions__share a'
  end

  test 'only public blog posts appear to visitors and photo-free posts do not show empty frames' do
    plain = @circle.blogs.create!(title: 'チームで練習しました', content: '練習の内容を振り返りました。' * 12)
    gallery = @circle.blogs.create!(title: '地域の大会に出場しました', content: '大会で対戦した皆さんに感謝しています。' * 12)
    hidden = @circle.blogs.create!(title: '公開されていない連絡', content: '内部向けに次回の連絡をまとめています。' * 12,
                                   moderation_status: 'blocked')
    example_image = Rails.root.join('public/images/events/basketball.jpg')
    File.open(example_image) { |file| gallery.image_01.store!(file) }
    File.open(example_image) { |file| gallery.image_02.store!(file) }
    gallery.update_columns(image_01: gallery.image_01.identifier, image_02: gallery.image_02.identifier)

    get circle_blogs_path(@circle)
    assert_response :success
    assert_select '.cb-public-circle--blogs .cb-public-circle__main article.cb-circle-blogs__card', count: 2
    assert_select '.cb-circle-blogs__card' do |cards|
      plain_card = cards.find { |card| card.at_css('h3').text == plain.title }
      gallery_card = cards.find { |card| card.at_css('h3').text == gallery.title }
      assert_empty plain_card.css('.cb-circle-blogs__media')
      assert_equal 2, gallery_card.css('.swiper-slide').size
      assert_equal circle_blog_path(@circle, gallery), gallery_card.at_css('a.cb-circle-blogs__article-link')['href']
    end
    assert_select 'a[href=?]', circle_blog_path(@circle, hidden), count: 0

    sign_in @owner
    get circle_blogs_path(@circle)
    assert_response :success
    assert_select '.cb-circle-blogs__visibility', text: 'このブログは現在、一般には公開されていません。'
    assert_select 'a.cb-circle-blogs__article-link[href=?]', circle_blog_path(@circle, hidden)
  ensure
    gallery&.image_01&.remove!
    gallery&.image_02&.remove!
  end
  test 'the public blog directory shares circle cards and retains filters and genre and area links' do
    visible = @circle.blogs.create!(title: '地域の練習会', content: '<p>みんなで練習しました。</p>' * 18)
    hidden = @circle.blogs.create!(title: '非公開の予定', content: '内部共有用のお知らせです。' * 18,
                                   moderation_status: 'blocked')

    get circle_blogs_path(@circle)
    assert_response :success
    card = css_select('.cb-circle-blogs__card').first
    expected = %w[.cb-circle-blogs__author time .cb-circle-blogs__title .cb-circle-blogs__excerpt .cb-circle-blogs__read]
      .to_h { |selector| [selector, card.at_css(selector).text.squish] }

    sign_in @owner
    [blogs_path, blogs_event_path(@circle.event.ruby), blogs_prefecture_path(@circle.prefecture.kana),
     blogs_event_prefecture_path(@circle.event.ruby, @circle.prefecture.kana)].each do |path|
      get path
      assert_response :success
      assert_select 'select[name=event_select], select[name=prefecture_select]', count: 2
      assert_select '.blog-directory-cards article.cb-circle-blogs__card', count: 1 do |cards|
        expected.each { |selector, text| assert_equal text, cards.first.at_css(selector).text.squish }
        assert_select 'a.cb-circle-blogs__article-link[href=?] h2.cb-circle-blogs__title', circle_blog_path(@circle, visible)
        assert_select '.cb-circle-blogs__tags a[href=?]', event_path(@circle.event.ruby), text: @circle.event.name
        assert_select '.cb-circle-blogs__tags a[href=?]', event_prefecture_path(@circle.event.ruby, @circle.prefecture.kana), text: @circle.prefecture.name
      end
      assert_select 'a[href=?]', circle_blog_path(@circle, hidden), count: 0
    end
  end

end
