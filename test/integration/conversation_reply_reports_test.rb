require 'test_helper'
require_relative '../support/chat_records'

class ConversationReplyReportsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  self.fixture_table_names = []
  include ChatRecords
  setup { create_chat_records }

  test 'owner reports a participant once after three days and a reply clears both profile displays' do
    accept_conversation
    sign_in @owner
    post no_reply_conversation_path(@conversation)
    assert_equal 0, @member.unanswered_report_count
    assert_equal 0, ConversationReplyReport.count
    travel 4.days do
      get conversation_path(@conversation)
      assert_select '#chat-no-reply[value="返信がないことを報告する"]'
      assert_select '.chat-composer-recipient', text: '参加者さくらさんへ'
      2.times { post no_reply_conversation_path(@conversation) }
      assert_equal 1, ConversationReplyReport.count
      assert_equal 1, @member.unanswered_report_count
      assert_nil @conversation.reload.respond_check
      get conversation_path(@conversation)
      assert_select '.chat-profile--member .chat-profile__no-reply', text: '返信なしの報告：1人'
      get member_profile_path(@member)
      assert_select '.circle-reply-notice strong', text: '1人から、返信がないとの報告があります'
      assert_not_includes css_select('.circle-reply-notice').first.text, @circle.name
      @conversation.send_message!('member', '返信が遅くなりました。参加します。')
      assert_equal 0, @member.unanswered_report_count
      get member_profile_path(@member)
      assert_select '.circle-reply-notice', count: 0
    end
  end

  test 'member can report missing replies after acceptance without adding an initial reply penalty' do
    accept_conversation
    @conversation.send_message!('member', '集合場所を詳しく教えてください。')
    sign_in @member
    travel 4.days do
      post no_reply_conversation_path(@conversation)
      assert_equal 1, @circle.unanswered_report_count
      get circle_path(@circle)
      assert_select '.circle-reply-notice strong', text: '1人から、返信がないとの報告があります'
      assert_nil @conversation.reload.respond_check
      assert_not Conversation.reported_unanswered.exists?(@conversation.id)
      @conversation.send_message!('owner', '体育館の正面入口に集合してください。')
      assert_equal 0, @circle.unanswered_report_count
      @conversation.send_message!('member', '次回の予定も教えてください。')
      assert_equal 0, @circle.unanswered_report_count, 'a resolved old report must not reappear for a new question'
      travel 4.days
      post no_reply_conversation_path(@conversation)
      assert_equal 1, @circle.unanswered_report_count
      assert_equal 1, ConversationReplyReport.count
    end
  end

  test 'unrelated accounts cannot report and a blocked conversation cannot create a report' do
    accept_conversation
    sign_in @other_member
    travel 4.days do
      assert_raises(ActiveRecord::RecordNotFound) { post no_reply_conversation_path(@conversation) }
      sign_out @other_member
      sign_in @owner
      @conversation.update!(owner_blocked: true)
      post no_reply_conversation_path(@conversation)
      assert_equal 0, ConversationReplyReport.count
      assert_equal 0, @member.unanswered_report_count
    end
  end

  test 'follow-up messages do not restart the wait and only the latest unanswered turn is reportable' do
    accept_conversation
    travel 4.days do
      @conversation.send_message!('owner', 'ご都合はいかがでしょうか？')
      @conversation.report_no_reply!('owner')
      assert_equal 1, @member.unanswered_report_count
      @conversation.send_message!('member', '確認して折り返します。')
      assert_equal 0, @member.unanswered_report_count
      assert_raises(Conversation::NotAllowed) { @conversation.report_no_reply!('owner') }
      @conversation.send_message!('owner', 'お返事をお待ちしています。')
      assert_raises(Conversation::NotAllowed) { @conversation.report_no_reply!('owner') }
    end
  end

  test 'held replies only clear a report when approved and released' do
    accept_conversation
    travel 4.days do
      @conversation.report_no_reply!('owner')
      reply = @conversation.chat_messages.create!(sender_role: 'member', body: '確認しました。', moderation_status: 'held')
      assert_equal 1, @member.unanswered_report_count
      reply.moderate!('approve')
      assert_equal 0, @member.unanswered_report_count
    end
  end

  test 'several circles managed by one organizer count as one reporting person' do
    another = @circle.dup
    another.name = '同じ主催者の別サークル'
    another.save!
    other = Conversation.for_member!(another, @member)
    other.send_message!('member', 'こちらにも参加したいです。')
    other.send_message!('owner', 'ご希望の日程を教えてください。')
    accept_conversation
    travel 4.days do
      @conversation.report_no_reply!('owner')
      other.report_no_reply!('owner')
      assert_equal 2, ConversationReplyReport.count
      assert_equal 1, @member.unanswered_report_count
    end
  end

  test 'a held outgoing inquiry starts its waiting period at release and excludes automatic messages' do
    message = @conversation.chat_messages.where(sender_role: 'member').sole
    message.update!(moderation_status: 'held', created_at: 10.days.ago)
    assert_nil @conversation.reply_reportable_at('member')
    assert_raises(Conversation::NotAllowed) { @conversation.report_no_reply!('member') }
    message.moderate!('approve')
    assert_in_delta 3.days.from_now.to_f, @conversation.reply_reportable_at('member').to_f, 1
    assert_raises(Conversation::NotAllowed) { @conversation.report_no_reply!('member') }
  end
end
