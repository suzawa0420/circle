require 'test_helper'
require_relative '../support/chat_records'
require_relative '../../db/migrate/20261003000000_remove_legacy_contact_score_penalties'
require_relative '../../db/migrate/20261010010000_reconcile_message_penalties'

class LegacyContactScoreTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    @conversation.chat_messages.where(sender_role: 'member').update_all(created_at: 4.days.ago)
    @circle.update!(user_time: Time.current.to_s)
    @circle.schedules.create!(title: '週末の練習', venue: '体育館', day: (Date.current + 7).to_s)
    UserContact.create!(user: @circle, name: '参加希望者', mail: 'legacy@example.test',
                        message: '練習に参加できますか？', respond_check: 'NG')
  end

  test 'legacy no reply reports do not lower the score' do
    CircleScoreUpdater.new.refresh(@circle)
    assert_in_delta 0.1, @circle.cb_point
  end

  test 'only new messages incur a penalty and an owner reply restores the score' do
    @conversation.update!(respond_check: 'NG')
    @conversation.refresh_circle_score!
    assert_in_delta(-29.9, @circle.reload.cb_point)

    accept_conversation
    assert_nil @conversation.reload.respond_check
    assert_in_delta 0.1, @circle.reload.cb_point
  end

  test 'undelivered recently released and accepted inquiries do not lower the score' do
    message = @conversation.chat_messages.where(sender_role: 'member').sole
    @conversation.update!(respond_check: 'NG')
    message.update_columns(moderation_status: 'held')
    CircleScoreUpdater.new.refresh(@circle)
    assert_in_delta 0.1, @circle.cb_point
    message.update_columns(moderation_status: 'approved', released_at: Time.current)
    CircleScoreUpdater.new.refresh(@circle)
    assert_in_delta 0.1, @circle.cb_point
    message.update_columns(released_at: 4.days.ago)
    CircleScoreUpdater.new.refresh(@circle)
    assert_in_delta(-29.9, @circle.cb_point)
    @conversation.update!(accepted_at: Time.current)
    CircleScoreUpdater.new.refresh(@circle)
    assert_in_delta 0.1, @circle.cb_point
  end

  test 'owner inbox and thread identify penalty and filtered list removes it after reply' do
    @conversation.update!(respond_check: 'NG')
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    get conversations_path
    assert_select '.chat-talk .chat-penalty-badge', text: '未返信報告 −30ポイント', count: 1
    get conversations_path(penalty: '1', circle_id: @circle.id)
    assert_select '.chat-talk', count: 1
    get conversation_path(@conversation)
    assert_select '.chat-penalty-summary', text: /返信すると減点が解除/
    get "/users/#{@circle.id}/mypage"
    assert_select ".dashboard-level__guide a[href='#{conversations_path(circle_id: @circle.id, penalty: '1')}']"
    assert_select '.dashboard-level__breakdown tbody tr', text: /メッセージ未返信.*-30.0/m
    post message_conversation_path(@conversation), params: { message: { body: 'お問い合わせありがとうございます。' } }
    assert_response :redirect
    get conversations_path(penalty: '1', circle_id: @circle.id)
    assert_select '.chat-talk', count: 0
    assert_select '.chat-penalty-badge', count: 0
    assert_select '.chat-card', text: /減点対象のメッセージはありません/
    assert_in_delta 0.1, @circle.reload.cb_point
  end

  test 'penalty filter never exposes another owner messages and badge is owner only' do
    @conversation.update!(respond_check: 'NG')
    post member_session_path, params: { member: { email: @member.email, password: 'test-password-123' } }
    get conversations_path(penalty: '1')
    assert_select '.chat-penalty-badge', count: 0
    get conversation_path(@conversation)
    assert_select '.chat-penalty-summary', count: 0
    delete destroy_member_session_path
    other = AdminUser.create!(email: 'penalty-other@example.test', password: 'test-password-123', email_verified_at: Time.current)
    post admin_user_session_path, params: { admin_user: { email: other.email, password: 'test-password-123' } }
    get conversations_path(penalty: '1', circle_id: @circle.id)
    assert_select '.chat-talk', count: 0
  end

  test 'reconciliation clears obsolete penalties preserves valid reports and activity timestamps' do
    @conversation.update!(respond_check: 'NG')
    @circle.update_columns(cb_point: -59.9)
    original_times = @circle.attributes.slice('updated_at', 'user_time', 'last_post')
    ReconcileMessagePenalties.new.up
    assert_in_delta(-29.9, @circle.reload.cb_point)
    assert_equal original_times, @circle.attributes.slice('updated_at', 'user_time', 'last_post')
    @conversation.chat_messages.where(sender_role: 'member').update_all(moderation_status: 'held')
    ReconcileMessagePenalties.new.up
    assert_in_delta 0.1, @circle.reload.cb_point
    assert_equal original_times, @circle.attributes.slice('updated_at', 'user_time', 'last_post')
    ReconcileMessagePenalties.new.up
    assert_in_delta 0.1, @circle.reload.cb_point
  end

  test 'backfill removes stored legacy penalties while preserving new penalties and activity times' do
    @circle.update_columns(cb_point: -59.9)
    @conversation.update!(respond_check: 'NG')
    original_times = @circle.attributes.slice('updated_at', 'user_time', 'last_post')

    RemoveLegacyContactScorePenalties.new.up

    assert_in_delta(-29.9, @circle.reload.cb_point)
    assert_equal original_times, @circle.attributes.slice('updated_at', 'user_time', 'last_post')
    assert_equal 'NG', UserContact.where(user: @circle).sole.respond_check

    @owner.update!(check: 1)
    RemoveLegacyContactScorePenalties.new.up
    assert_equal(-100, @circle.reload.cb_point)

    @owner.update!(check: nil)
    @circle.update_columns(user_time: 2.years.ago.to_s)
    RemoveLegacyContactScorePenalties.new.up
    assert_equal 0, @circle.reload.cb_point
  end
end
