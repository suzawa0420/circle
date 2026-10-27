require 'test_helper'
require_relative '../support/chat_records'

class ChatReportGuidanceTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    accept_conversation
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
  end

  test 'eligible organizer gets the existing participant review link before the report form' do
    get conversation_path(@conversation)
    assert_response :success
    assert_select '.chat-message__report > .chat-report-guidance + form[action=?]', report_conversation_path(@conversation)
    assert_select '.chat-report-guidance' do
      assert_select 'a[href="#evaluation"][data-open-evaluation]', text: '参加者への口コミを書く'
      assert_select 'a[href*=reviews]', count: 0
      assert_select 'p', text: /確認できた事実.*個人情報/
      assert_select 'p', text: /脅迫・嫌がらせ・詐欺.*通報を続けられます/
    end
    assert_select '#evaluation form[action=?]', review_conversation_path(@conversation)
  end

  test 'before a reply and after the review window no review link is offered but reporting remains' do
    @conversation.update_columns(accepted_at: nil)
    assert_guidance_without_review
    @conversation.update_columns(accepted_at: 40.days.ago, review_deadline: 1.day.ago)
    assert_guidance_without_review
  end

  test 'unverified or suspended organizers do not get an unusable review link' do
    @owner.update_columns(email_verified_at: nil)
    assert_guidance_without_review
    @owner.update_columns(email_verified_at: Time.current, suspended_at: Time.current)
    assert_guidance_without_review
  end

  test 'deleted or published own review cannot be presented as writable' do
    review = @conversation.conversation_reviews.create!(author_role: 'owner', score: 0,
      comment: '事前の連絡についての感想です。', deleted_at: Time.current)
    assert_guidance_without_review
    review.update_columns(deleted_at: nil, published_at: Time.current)
    assert_guidance_without_review
  end

  test 'member and practice-match reports are not directed to participant reviews' do
    delete destroy_admin_user_session_path
    post member_session_path, params: { member: { email: @member.email, password: 'test-password-123' } }
    get conversation_path(@conversation)
    assert_select '.chat-report-guidance', count: 0
    assert_select '.chat-message__report form[action=?]', report_conversation_path(@conversation)
    delete destroy_member_session_path
    source_owner = AdminUser.create!(email: 'guidance-source@example.test', password: 'test-password-123', email_verified_at: Time.current)
    source = @circle.dup
    source.assign_attributes(name: '対戦相手のチーム', admin_user: source_owner, unique_id: nil)
    source.save!
    practice = Conversation.for_circles!(@circle, source)
    practice.send_message!('member', '練習試合について相談したいです。')
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    get conversation_path(practice)
    assert_select '.chat-report-guidance, #evaluation', count: 0
    assert_select '.chat-message__report form[action=?]', report_conversation_path(practice)
  end

  test 'polled messages keep guidance without disclosing the peers private review' do
    @conversation.conversation_reviews.create!(author_role: 'member', score: 0, comment: 'まだ非公開の相手の感想です。')
    get messages_conversation_path(@conversation), as: :json
    assert_response :success
    fragment = Nokogiri::HTML.fragment(response.parsed_body.fetch('html'))
    assert fragment.at_css('.chat-report-guidance a[href="#evaluation"]')
    refute_includes response.body, 'まだ非公開の相手の感想です。'
    assert_equal 1, fragment.css('input[name=message_id]').length
  end

  test 'genuine reports still save normally without reviews or status changes on existing reports' do
    previous = @conversation.chat_reports.create!(reporter_role: 'owner', reason: '以前に相談した内容です。', status: 'in_progress')
    @owner.update_columns(email_verified_at: nil)
    message = @conversation.chat_messages.find_by!(sender_role: 'member')
    assert_no_difference 'ConversationReview.count' do
      assert_difference 'ChatReport.count', 1 do
        post report_conversation_path(@conversation), params: { message_id: message.id,
          report: { reason: '脅迫と思われる連絡があり、安全面を確認してほしいです。' } }
      end
    end
    assert_redirected_to conversation_path(@conversation)
    assert_equal 'pending', @conversation.chat_reports.order(:id).last.status
    assert_equal 'in_progress', previous.reload.status
  end

  test 'another account cannot inspect guidance or report targets from this conversation' do
    delete destroy_admin_user_session_path
    post member_session_path, params: { member: { email: @other_member.email, password: 'test-password-123' } }
    assert_raises(ActiveRecord::RecordNotFound) { get conversation_path(@conversation) }
    assert_raises(ActiveRecord::RecordNotFound) { get messages_conversation_path(@conversation), as: :json }
  end

  private

  def assert_guidance_without_review
    get conversation_path(@conversation)
    assert_response :success
    assert_select '.chat-report-guidance', count: 1
    assert_select '.chat-report-guidance a', count: 0
    assert_select '.chat-report-guidance p', text: /現在は口コミを投稿・編集できません/
    assert_select '.chat-message__report form[action=?] textarea[required][name="report[reason]"]', report_conversation_path(@conversation)
  end
end
