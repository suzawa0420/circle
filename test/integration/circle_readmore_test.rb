require 'test_helper'
require_relative '../support/chat_records'

class CircleReadmoreTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup { create_chat_records }

  test 'each long section has an independent accessible expand control and keeps its content' do
    @circle.update!(appeal: '<div>' + ('サークルでの活動内容です。<br>' * 80) + '</div>')
    @owner.update!(open: 1, nickname: '主催者さくら', profile: '地域で楽しく活動しています。' * 80)
    8.times { |i| @circle.questions.create!(content: "質問その#{i}は？", answer: '初心者も参加できます。') }
    3.times { |i| @circle.reviews.create!(review: 1, comment: "楽しく参加できました。#{i}" * 20) }
    6.times do |i|
      blog = @circle.blogs.create!(title: "活動ブログ#{i}", content: '地域で楽しく活動しています。' * 15)
      blog.update_columns(moderation_status: 'clear')
    end
    get circle_path(@circle)
    assert_response :success
    %w[introduction reviews questions blogs organizer].each do |section|
      assert_select ".circle-readmore--#{section}", count: 1 do
        assert_select "#circle-#{section}-content.circle-readmore__content", count: 1
        assert_select "button[aria-controls='circle-#{section}-content'][aria-expanded=false][hidden]", count: 1
        assert_select '.circle-readmore__body', count: 1
      end
    end
    assert_select '.circle-faq__item', count: 8
    assert_select '.review_contents', count: 3
    assert_select '.circle-readmore--blogs .blog_title', count: 5
    assert_select '.circle-readmore__archive a[href=?]', circle_blogs_path(@circle)
    assert_select '.review_link_b a[href=?]', user_reviews_path(@circle)
    assert_select '.cb-reading-body', text: /サークルでの活動内容です/
    assert_select '.circle-readmore--organizer .admin_user_txt', text: @owner.profile
    assert_select '#check_admin_prof, .admin_user_profile_wrap .readmore-label', count: 0
  end

  test 'short organizer profiles use the shared control without losing their text' do
    @owner.update!(open: 1, nickname: '主催者さくら', profile: 'よろしくお願いします。')
    get circle_path(@circle)
    assert_response :success
    assert_select '.circle-readmore--organizer .admin_user_txt', text: 'よろしくお願いします。'
    assert_select '.circle-readmore--organizer button[hidden][aria-controls=circle-organizer-content]'
  end

  test 'private organizer profiles remain hidden' do
    @owner.update!(open: 0, nickname: '非公開の主催者', profile: '非公開の紹介文です。' * 50)
    get circle_path(@circle)
    assert_response :success
    assert_select '.circle-readmore--organizer', count: 0
    refute_includes response.body, @owner.profile
  end

  test 'empty sections do not have expand controls' do
    get circle_path(@circle)
    assert_response :success
    assert_select '.circle-readmore--introduction', count: 1
    %w[reviews questions blogs].each { |section| assert_select ".circle-readmore--#{section}", count: 0 }
  end

  test 'public detail asset retains gradient controls and collapsed states' do
    css = Rails.application.assets.find_asset('public_detail.css').to_s
    %w[.circle-readmore__button .circle-readmore__content .circle-readmore__body .circle-readmore__chevron .is-collapsed].each do |selector|
      assert_includes css, selector
    end
    assert_includes css, 'linear-gradient('
    assert_includes css, 'prefers-reduced-motion'
  end

  test 'readmore stylesheet can compile independently through the asset manifest' do
    css = Rails.application.assets.find_asset('_circle_readmore.css').to_s
    assert_includes css, '.circle-readmore__button'
    assert_includes css, '.circle-readmore--organizer'
  end

  test 'public detail JavaScript includes the shared readmore and video controls' do
    javascript = Rails.application.assets.find_asset('public_detail.js').to_s
    %w[data-circle-readmore data-circle-video-open .circle-faq__question].each do |selector|
      assert_includes javascript, selector
    end
  end
end
