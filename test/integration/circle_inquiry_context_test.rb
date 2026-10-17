require 'test_helper'
require 'minitest/mock'
require_relative '../support/chat_records'

class CircleInquiryContextTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    @schedule = @circle.schedules.create!(day: '2026-10-25', title: '体験バスケ', time_s: '18:00', time_e: '21:00', venue: '公開体育館', member_venue: '秘密の集合場所', venue_address: '非公開住所')
    @blog = @circle.blogs.create!(title: '週末の活動報告', content: '皆さんで楽しく活動しました。' * 12)
    @question = @circle.questions.create!(content: '一人でも参加できますか？')
  end

  test 'each public menu has an inquiry button carrying the verified source' do
    {circle_path(@circle) => 'details', user_schedules_path(@circle) => 'schedules', user_schedule_path(@circle, @schedule) => 'schedule', user_reviews_path(@circle) => 'reviews', user_questions_path(@circle) => 'questions', user_question_path(@circle, @question) => 'question', circle_blogs_path(@circle) => 'blogs', circle_blog_path(@circle, @blog) => 'blog'}.each do |path, kind|
      get path
      assert_response :success, path
      link = css_select('a[data-circle-inquiry-click]').first
      assert link, path
      token = Rack::Utils.parse_nested_query(URI(link['href']).query)['inquiry_context']
      context = CircleInquiryContext.resolve(@circle, token)
      assert_equal kind, context&.fetch('kind'), path
      assert_equal path, context.fetch('path'), path
      assert_not_includes context.to_json, '秘密の集合場所'
      assert_not_includes context.to_json, '非公開住所'
    end
  end

  test 'source preview and attachment work in an existing conversation without changing the body' do
    sign_in @member
    token = CircleInquiryContext.issue(@circle, kind: 'schedule', record_id: @schedule.id)
    get new_user_conversation_path(@circle, inquiry_context: token)
    assert_response :success
    assert_select '.chat-inquiry-preview .chat-inquiry-context', text: /活動日.*2026年10月25日.*18:00〜21:00.*体験バスケ/m
    assert_select 'input[name=inquiry_context][value=?]', token
    assert_select 'select[name*=inquiry], input[type=radio][name*=inquiry]', count: 0
    body = '参加を希望しています。よろしくお願いします。'
    assert_no_difference('Conversation.count') do
      assert_difference('ChatMessage.count', 1) { post user_conversations_path(@circle), params: { inquiry_context: token, message: { body: body } } }
    end
    message = @conversation.chat_messages.order(:id).last
    assert_equal body, message.body
    assert_equal 'schedule', message.inquiry_context['kind']
    assert_equal user_schedule_path(@circle, @schedule), message.inquiry_context['path']
    get conversation_path(@conversation)
    assert_select "#chat-message-#{message.id} > .chat-inquiry-context", text: /システムからの案内.*お問い合わせ元：活動日ページ.*体験バスケ/m
    assert_select "#chat-message-#{message.id} .chat-body .chat-inquiry-context", count: 0
    sign_out @member
    sign_in @owner
    get conversation_path(@conversation)
    assert_select "#chat-message-#{message.id} > .chat-inquiry-context", text: /システムからの案内.*お問い合わせ元：活動日ページ.*体験バスケ/m
    assert_select "#chat-message-#{message.id} .chat-body .chat-inquiry-context", count: 0
  end

  test 'source descriptions name the page and omit redundant circle names' do
    sign_in @member
    { 'details' => 'サークル詳細', 'schedules' => '活動日一覧', 'reviews' => '口コミ', 'questions' => 'Q&A', 'blogs' => 'ブログ一覧' }.each do |kind, label|
      token = CircleInquiryContext.issue(@circle, kind: kind)
      get new_user_conversation_path(@circle, inquiry_context: token)
      assert_response :success
      assert_select '.chat-inquiry-context__description', text: "お問い合わせ元：#{label}ページ"
      assert_select '.chat-inquiry-context__link', count: 0
      assert_select '.chat-inquiry-context', text: /#{Regexp.escape(@circle.name)}/, count: 0
    end
    # Existing stored context gets the updated presentation too.
    @conversation.chat_messages.where(sender_role: 'member').first.update!(inquiry_context: CircleInquiryContext.build(@circle, 'details', nil))
    get conversation_path(@conversation)
    assert_select '.chat-inquiry-context__description', text: 'お問い合わせ元：サークル詳細ページ'
    assert_select '.chat-inquiry-context__link', count: 0
  end

  test 'forged cross-circle and hidden sources are not accepted' do
    token = CircleInquiryContext.issue(@circle, kind: 'blog', record_id: @blog.id)
    assert_nil CircleInquiryContext.resolve(@circle, token + 'forged')
    other = @circle.dup.tap { |circle| circle.name = '別のサークル'; circle.save! }
    assert_nil CircleInquiryContext.resolve(other, token)
    assert_nil CircleInquiryContext.issue(other, kind: 'blog', record_id: @blog.id)
    @blog.update_columns(moderation_status: 'blocked')
    assert_nil CircleInquiryContext.resolve(@circle, token)
    @schedule.destroy!
    assert_nil CircleInquiryContext.issue(@circle, kind: 'schedule', record_id: @schedule.id)
    sign_in @member
    post user_conversations_path(@circle), params: { inquiry_context: 'forged', message: { body: '参加方法を教えてください。', inquiry_context: { path: 'https://example.test' } } }
    assert_empty @conversation.chat_messages.order(:id).last.inquiry_context
  end

  test 'held inquiries keep their source private with the held message' do
    sign_in @member
    token = CircleInquiryContext.issue(@circle, kind: 'reviews')
    result = Struct.new(:score, :reasons, :fingerprint, :held?).new(100, ['test'], 'test-context', true)
    ChatSpamDetector.stub(:evaluate, result) do
      post user_conversations_path(@circle), params: { inquiry_context: token, message: { body: '口コミを見て参加を希望しています。' } }
    end
    message = @conversation.chat_messages.order(:id).last
    assert_equal 'held', message.moderation_status
    assert_equal 'reviews', message.inquiry_context['kind']
    sign_out @member
    sign_in @owner
    get conversation_path(@conversation)
    assert_select "#chat-message-#{message.id}", count: 0
  end
  test 'a first inquiry preserves the full body and source through the registration return URL' do
    token = CircleInquiryContext.issue(@circle, kind: 'blog', record_id: @blog.id)
    destination = new_user_conversation_path(@circle, inquiry_context: token)
    get destination
    assert_redirected_to new_member_registration_path
    assert_equal destination, session['member_return_to']
    sign_in @other_member
    get destination
    assert_response :success
    body = ('参加を希望しています。' * 200).first(2000)
    assert_difference('Conversation.count', 1) do
      post user_conversations_path(@circle), params: { inquiry_context: token, message: { body: body } }
    end
    conversation = Conversation.find_by!(user: @circle, member: @other_member)
    message = conversation.chat_messages.where(sender_role: 'member').last
    assert_equal body, message.body
    assert_equal @blog.title, message.inquiry_context['title']
    @blog.update_columns(title: '更新後の記事名')
    assert_equal '週末の活動報告', message.reload.inquiry_context['title']
  end

  test 'preview escapes page titles and only uses canonical local links' do
    @blog.update_columns(title: '<script>alert(1)</script> 活動レポート')
    token = CircleInquiryContext.issue(@circle, kind: 'blog', record_id: @blog.id)
    sign_in @member
    get new_user_conversation_path(@circle, inquiry_context: token)
    assert_select '.chat-inquiry-context script', count: 0
    assert_select '.chat-inquiry-context__link[href=?]', circle_blog_path(@circle, @blog), text: @blog.title, count: 1
  end

  private

  def sign_in(account)
    if account.is_a?(Member)
      post member_session_path, params: { member: { email: account.email, password: 'test-password-123' } }
    else
      post admin_user_session_path, params: { admin_user: { email: account.email, password: 'test-password-123' } }
    end
    assert_response :redirect
  end

  def sign_out(account)
    delete(account.is_a?(Member) ? destroy_member_session_path : destroy_admin_user_session_path)
    assert_response :redirect
  end

end
