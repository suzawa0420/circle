require 'test_helper'
require_relative '../support/chat_records'

class PracticeMatchConversationsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    @source_owner = AdminUser.create!(email: 'practice-owner@example.test', password: 'test-password-123', email_verified_at: Time.current)
    @source = @circle.dup
    @source.assign_attributes(name: '練習相手チーム', admin_user: @source_owner)
    @source.save!
    @circle.create_match!(recruit: '募集中')
    @source.create_match!(recruit: '募集中')
  end

  def start_practice
    sign_in @source_owner
    post user_conversations_path(@circle), params: { kind: 'practice_match', source_user_id: @source.id, message: { body: '来月の日曜日に練習試合をお願いできますか？' } }
    @practice = Conversation.find_by!(source_user: @source, user: @circle)
  end

  test 'organizers exchange messages without participant guidance or evaluation and reuse reverse pair' do
    sign_in @source_owner
    get new_user_conversation_path(@circle, kind: 'practice_match')
    assert_response :success
    assert_select 'select[name=source_user_id] option', text: @source.name
    assert_select '.inquiry-guidance', count: 0
    start_practice
    assert_redirected_to conversation_path(@practice)
    assert_nil @practice.member_id
    assert_equal ['member'], @practice.chat_messages.pluck(:sender_role)
    follow_redirect!
    assert_response :success
    assert_select 'h1', text: '対戦・練習試合の相談'
    assert_select '#evaluation, #chat-acceptance-status, #chat-no-reply', count: 0
    assert_select 'a[href=?]', circle_path(@source)
    get conversations_path
    assert_response :success
    assert_select '.chat-talk__name', text: @circle.name
    sign_out @source_owner
    sign_in @owner
    get conversation_path(@practice)
    assert_response :success
    assert_equal @practice.chat_messages.maximum(:id), @practice.reload.owner_read_message_id
    assert_no_difference 'Conversation.count' do
      post user_conversations_path(@source), params: { kind: 'practice_match', source_user_id: @circle.id, message: { body: 'ぜひお願いします。会場を相談しましょう。' } }
    end
    assert_redirected_to conversation_path(@practice)
    assert_equal %w[member owner], @practice.chat_messages.order(:id).pluck(:sender_role)
    assert_nil @practice.reload.accepted_at
    assert_nil @practice.review_deadline
    get conversations_path(circle_id: @circle.id)
    assert_select '.chat-talk__name', text: @source.name
    sign_out @owner
    sign_in @source_owner
    get messages_conversation_path(@practice)
    assert_response :success
    assert_equal @practice.chat_messages.maximum(:id), @practice.reload.member_read_message_id
  end

  test 'practice entry requires organizer login and email verification' do
    sign_in @member
    get new_user_conversation_path(@circle, kind: 'practice_match')
    assert_redirected_to new_admin_user_session_path
    sign_out @member
    @source_owner.update!(email_verified_at: nil)
    sign_in @source_owner
    get new_user_conversation_path(@circle, kind: 'practice_match')
    assert_redirected_to admin_user_email_verification_path
    assert_no_difference 'ChatMessage.count' do
      post user_conversations_path(@circle), params: { kind: 'practice_match', source_user_id: @source.id, message: { body: '練習試合の相談です。' } }
    end
    assert_redirected_to admin_user_email_verification_path
  end

  test 'cannot impersonate another circle or contact own or closed circles' do
    sign_in @source_owner
    assert_no_difference 'Conversation.count' do
      assert_raises(ActiveRecord::RecordNotFound) do
        post user_conversations_path(@circle), params: { kind: 'practice_match', source_user_id: @circle.id, message: { body: '練習試合の相談です。' } }
      end
      post user_conversations_path(@source), params: { kind: 'practice_match', source_user_id: @source.id, message: { body: '練習試合の相談です。' } }
      assert_response :redirect
      @circle.match.update!(recruit: '募集終了')
      post user_conversations_path(@circle), params: { kind: 'practice_match', source_user_id: @source.id, message: { body: '練習試合の相談です。' } }
      assert_response :redirect
    end
  end

  test 'unrelated members and organizers cannot read or post and review penalty endpoints reject organizers' do
    start_practice
    assert_no_difference 'ConversationReview.count' do
      put review_conversation_path(@practice), params: { evaluation: member_evaluation }
    end
    post no_reply_conversation_path(@practice)
    assert_nil @practice.reload.respond_check
    assert_not Conversation.reported_unanswered.exists?(@practice.id)
    sign_out @source_owner
    sign_in @member
    assert_raises(ActiveRecord::RecordNotFound) { get conversation_path(@practice) }
    assert_raises(ActiveRecord::RecordNotFound) do
      post message_conversation_path(@practice), params: { message: { body: '送信できません。' } }
    end
    sign_out @member
    outsider = AdminUser.create!(email: 'outsider@example.test', password: 'test-password-123', email_verified_at: Time.current)
    outsider_circle = @circle.dup
    outsider_circle.admin_user = outsider
    outsider_circle.save!
    sign_in outsider
    assert_raises(ActiveRecord::RecordNotFound) { get messages_conversation_path(@practice) }
  end

  test 'blocking suspension and reports remain available to both organizers' do
    start_practice
    post block_conversation_path(@practice)
    assert @practice.reload.member_blocked?
    assert_no_difference 'ChatMessage.count' do
      post message_conversation_path(@practice), params: { message: { body: 'ブロック中の送信です。' } }
    end
    delete block_conversation_path(@practice)
    @source_owner.update!(suspended_at: Time.current)
    assert_no_difference 'ChatMessage.count' do
      post message_conversation_path(@practice), params: { message: { body: '停止中の送信です。' } }
    end
    sign_out @source_owner
    sign_in @owner
    assert_difference 'ChatReport.count' do
      post report_conversation_path(@practice), params: { report: { reason: '相談内容の確認をお願いします。' }, message_id: @practice.chat_messages.first.id }
    end
  end

  test 'notifications address each organizer and source circle deletion removes its conversation' do
    start_practice
    assert_equal [@owner.email], ChatMailer.new_messages(@practice, 'owner').to
    assert_equal [@source_owner.email], ChatMailer.new_messages(@practice, 'member').to
    assert_includes ChatMailer.new_messages(@practice, 'owner').subject, @source.name
    @source.destroy!
    assert_not Conversation.exists?(@practice.id)
  end

  test 'match entry uses practice kind while ordinary participation keeps guidance' do
    get match_path(@circle)
    assert_response :success
    assert_select 'a[href=?]', new_user_conversation_path(@circle, kind: 'practice_match')
    sign_in @member
    get new_user_user_contact_path(@circle, entry: '2')
    assert_redirected_to new_user_conversation_path(@circle, kind: 'practice_match')
    get conversation_path(@conversation)
    assert_response :success
    assert_select '#evaluation'
  end
  test 'photos are private to both organizers and webmaster can inspect the practice conversation' do
    start_practice
    photo = Tempfile.new(['practice-chat', '.png'])
    MiniMagick::Tool.new('convert') { |c| c.size '100x100'; c.xc 'white'; c << photo.path }
    post message_conversation_path(@practice), params: { message: { image: Rack::Test::UploadedFile.new(photo.path, 'image/png') } }
    message = @practice.chat_messages.order(:id).last
    assert message.image?
    path = chat_image_path(@practice.public_id, message.id)
    get path
    assert_response :success
    sign_out @source_owner
    sign_in @owner
    get path
    assert_response :success
    sign_out @owner
    sign_in @other_member
    assert_raises(ActiveRecord::RecordNotFound) { get path }
    sign_out @other_member
    master = Webmaster.create!(id: 1, email: 'practice-master@example.test', password: 'test-password-123')
    post webmaster_session_path, params: { webmaster: { email: master.email, password: 'test-password-123' } }
    get super_admin_conversations_path
    assert_response :success
    get super_admin_conversation_path(@practice)
    follow_redirect!
    assert_response :success
    assert_select '.chat-profile', count: 2
    assert_select 'a[href=?]', super_admin_account_path(@source_owner, kind: 'owner')
  ensure
    message&.image&.remove!
    photo&.close!
  end

  test 'empty initial submission creates no orphan conversation and account limit is enforced' do
    sign_in @source_owner
    assert_no_difference 'Conversation.count' do
      post user_conversations_path(@circle), params: { kind: 'practice_match', source_user_id: @source.id, message: { body: '' } }
    end
    assert_redirected_to new_user_conversation_path(@circle, kind: 'practice_match')
    20.times do
      target = @circle.dup
      target.save!
      Conversation.for_circles!(target, @source)
    end
    assert_no_difference 'ChatMessage.count' do
      post user_conversations_path(@circle), params: { kind: 'practice_match', source_user_id: @source.id, message: { body: '練習試合の相談です。' } }
    end
    assert_includes flash[:alert], '上限'
  end

  test 'webmaster labels practice and participation across inbox reports moderation and account pages' do
    start_practice
    @practice.update!(member_blocked: true)
    report = @practice.chat_reports.create!(reporter_role: 'member', reason: '練習試合の相談について確認をお願いします。')
    held = @practice.chat_messages.create!(sender_role: 'member', body: '確認対象の相談です。', moderation_status: 'held')
    sign_out @source_owner
    master = Webmaster.create!(id: 1, email: 'practice-label-master@example.test', password: 'test-password-123')
    post webmaster_session_path, params: { webmaster: { email: master.email, password: 'test-password-123' } }
    get super_admin_conversations_path
    assert_response :success
    assert_select '[data-conversation-kind="practice_match"]', text: '対戦・練習試合'
    assert_select '[data-conversation-kind="participation"]', text: '参加の相談'
    assert_select '.wm-read-receipt', text: /主催者（#{@circle.name}）/
    get super_admin_conversation_path(@practice)
    follow_redirect!
    assert_response :success
    assert_select '[data-conversation-kind="practice_match"]', text: '対戦・練習試合'
    assert_select '.wm-badge', text: 'ブロック中'
    get super_admin_chat_reports_path
    assert_response :success
    assert_select '[data-conversation-kind="practice_match"]'
    get super_admin_chat_report_path(report)
    assert_response :success
    assert_select '[data-conversation-kind="practice_match"]'
    assert_select '.wm-meta', text: /通報者：主催者（#{@source.name}）/
    get super_admin_chat_moderations_path
    assert_response :success
    assert_select '[data-conversation-kind="practice_match"]'
    get super_admin_account_path(@source_owner, kind: 'owner')
    assert_response :success
    assert_select '[data-conversation-kind="practice_match"]', count: 2
    assert_select 'p', text: "通報者：主催者（#{@source.name}）"
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
