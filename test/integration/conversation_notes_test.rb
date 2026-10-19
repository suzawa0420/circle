require 'test_helper'
require_relative '../support/chat_records'

class ConversationNotesTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup { create_chat_records }

  test 'each participant has a private note without changing messages or read state' do
    sign_in @member
    before = @conversation.attributes
    assert_no_difference 'ChatMessage.count' do
      save_note '参加者だけのメモ'
    end
    assert_equal before, @conversation.reload.attributes
    get conversations_path
    assert_select '.chat-private-note input[value="参加者だけのメモ"]'
    assert_select '.chat-private-note', count: 1
    assert_select 'a .chat-private-note', count: 0
    assert_select '.chat-talk__circle, .chat-talk__status', count: 0
    sign_out @member
    sign_in @owner
    get conversations_path
    assert_not_includes response.body, '参加者だけのメモ'
    save_note '主催者だけのメモ'
    get conversations_path
    assert_select '.chat-private-note input[value="主催者だけのメモ"]'
    get conversation_path(@conversation)
    assert_not_includes response.body, '主催者だけのメモ'
    get messages_conversation_path(@conversation), as: :json
    assert_not_includes response.body, '主催者だけのメモ'
    sign_out @owner
    sign_in @member
    get conversations_path
    assert_includes response.body, '参加者だけのメモ'
    assert_not_includes response.body, '主催者だけのメモ'
    assert_equal 2, ConversationNote.count
  end

  test 'outsiders and unauthenticated requests cannot write notes and author fields are ignored' do
    patch private_note_conversation_path(@conversation), params: { note: { body: '未ログイン' } }, as: :json
    assert_redirected_to login_path
    sign_in @other_member
    assert_raises(ActiveRecord::RecordNotFound) { save_note '他人の会話' }
    assert_equal 0, ConversationNote.count
    sign_out @other_member
    sign_in @member
    patch private_note_conversation_path(@conversation), params: { note: { body: '本人のメモ', member_id: @other_member.id, admin_user_id: @owner.id } }, as: :json
    assert_response :success
    assert_equal @member.id, ConversationNote.sole.member_id
    assert_nil ConversationNote.sole.admin_user_id
  end

  test 'notes can be updated and cleared but overlong text preserves saved content' do
    sign_in @member
    save_note '10/24 参加予定'
    save_note '持ち物を連絡済み'
    assert_equal 1, ConversationNote.count
    patch private_note_conversation_path(@conversation), params: { note: { body: 'あ' * 301 } }, as: :json
    assert_response :unprocessable_entity
    assert_equal '持ち物を連絡済み', ConversationNote.sole.body
    save_note ''
    assert_equal '', ConversationNote.sole.body
  end

  test 'master conversation report and account pages do not expose private notes' do
    sign_in @owner
    save_note '非公開の参加予定と個人的なメモ'
    sign_out @owner
    master = Webmaster.create!(id: 1, email: 'private-note-master@example.test', password: 'test-password-123')
    report = @conversation.chat_reports.create!(reporter_role: 'member', reason: '確認をお願いします。')
    post webmaster_session_path, params: { webmaster: { email: master.email, password: 'test-password-123' } }
    [super_admin_conversations_path, super_admin_conversation_path(@conversation, page: 1), super_admin_chat_report_path(report), super_admin_account_path(@owner, kind: 'owner')].each do |path|
      get path
      assert_response :success
      assert_not_includes response.body, '非公開の参加予定と個人的なメモ'
    end
  end

  test 'both practice match organizers keep independent notes even when managing several circles' do
    other = AdminUser.create!(email: 'note-practice@example.test', password: 'test-password-123', email_verified_at: Time.current)
    source = @circle.dup
    source.update!(name: '練習相手サークル', admin_user: other)
    practice = Conversation.for_circles!(@circle, source)
    practice.send_message!('member', '練習試合をお願いします。')
    [[other, '相談を開始した側のメモ'], [@owner, '相談を受けた側のメモ']].each do |account, text|
      sign_in account
      patch private_note_conversation_path(practice), params: { note: { body: text } }, as: :json
      assert_response :success
      get conversations_path
      assert_select "input[value=?]", text
      assert_select '[data-private-note]', count: account == @owner ? 2 : 1
      sign_out account
    end
    assert_equal 2, practice.conversation_notes.count
  end

  test 'changing a circle owner does not hand private notes to the new owner' do
    sign_in @owner
    save_note '以前の主催者だけのメモ'
    sign_out @owner
    replacement = AdminUser.create!(email: 'replacement-note@example.test', password: 'test-password-123', email_verified_at: Time.current)
    @circle.update!(admin_user: replacement)
    sign_in replacement
    get conversations_path
    assert_not_includes response.body, '以前の主催者だけのメモ'
    save_note '新しい主催者のメモ'
    assert_equal 2, @conversation.conversation_notes.count
  end

  test 'inbox sorts by own memo or visible message activity while peer notes and reads stay private' do
    other = Conversation.for_member!(@circle, @other_member)
    message = other.send_message!('member', 'こちらも参加希望です。')
    @conversation.chat_messages.update_all(created_at: 3.hours.ago, updated_at: 3.hours.ago)
    message.update_columns(created_at: 2.hours.ago, updated_at: 2.hours.ago)
    sign_in @owner
    assert_inbox_order other, @conversation
    save_note '日程を確認する'
    assert_inbox_order @conversation, other
    peer_note = other.conversation_notes.create!(member: @other_member, body: '相手に見えないメモ')
    peer_note.update_columns(updated_at: 1.day.from_now)
    assert_inbox_order @conversation, other
    message.update_columns(edited_at: 1.minute.from_now)
    assert_inbox_order other, @conversation
    @conversation.chat_messages.where(sender_role: 'member').first.update_column(:recipient_read_at, 2.minutes.from_now)
    assert_inbox_order other, @conversation
    @conversation.chat_messages.where(sender_role: 'member').first.update_column(:deleted_at, 3.minutes.from_now)
    assert_inbox_order @conversation, other
  end

  test 'own memo sorting is applied before pagination and supports participant accounts' do
    @conversation.chat_messages.update_all(created_at: 2.days.ago, updated_at: 2.days.ago)
    20.times do |index|
      circle = @circle.dup
      circle.update!(name: "並び順検証#{index}")
      conversation = Conversation.for_member!(circle, @member)
      conversation.chat_messages.create!(sender_role: 'owner', body: '新しいメッセージ', created_at: 1.day.ago)
    end
    sign_in @member
    get conversations_path
    assert_select 'form[action=?]', private_note_conversation_path(@conversation), count: 0
    save_note '次の参加予定を記録'
    get conversations_path
    assert_select '.chat-talk-item', count: 20
    assert_select '.chat-talk-item:first-child form[action=?]', private_note_conversation_path(@conversation)
  end

  test 'a held peer message never changes the recipients order' do
    other = Conversation.for_member!(@circle, @other_member)
    other.send_message!('member', '参加を希望します。')
    @conversation.chat_messages.update_all(created_at: 1.hour.ago, updated_at: 1.hour.ago)
    held = @conversation.chat_messages.create!(sender_role: 'member', body: '未配信', moderation_status: 'held', edited_at: 1.day.from_now)
    sign_in @owner
    assert_inbox_order other, @conversation
    held.moderate!('approve')
    assert_inbox_order @conversation, other
  end

  test 'practice match notes sort only for their author and dual logins use the displayed account' do
    source_owner = AdminUser.create!(email: 'note-order-practice@example.test', password: 'test-password-123', email_verified_at: Time.current)
    source = @circle.dup
    source.update!(name: '並び順検証チーム', admin_user: source_owner)
    practice = Conversation.for_circles!(@circle, source)
    practice.chat_messages.create!(sender_role: 'member', body: '対戦相談', created_at: 1.hour.ago)
    note = practice.conversation_notes.create!(admin_user: source_owner, body: '相談側のメモ')
    note.update_column(:updated_at, 1.day.from_now)
    sign_in @owner
    assert_inbox_order @conversation, practice
    practice.conversation_notes.create!(admin_user: @owner, body: '受信側のメモ')
    assert_inbox_order practice, @conversation
    sign_in @member
    # The ordinary thread now shows the participant side, so the owner's note must not affect it.
    @conversation.conversation_notes.create!(admin_user: @owner, body: '主催者側のみ', updated_at: 2.days.from_now)
    assert_inbox_order practice, @conversation
  end

  private

  def assert_inbox_order(*conversations)
    get conversations_path
    assert_response :success
    assert_equal conversations.map { |conversation| conversation_path(conversation) }, css_select('.chat-talk').map { |link| link['href'].split('#').first }
  end

  def sign_in(account)
    scope = account.is_a?(Member) ? :member : :admin_user
    post public_send("#{scope}_session_path"), params: { scope => { email: account.email, password: 'test-password-123' } }
    assert_response :redirect
  end

  def sign_out(account)
    delete(account.is_a?(Member) ? destroy_member_session_path : destroy_admin_user_session_path)
  end

  def save_note(body)
    patch private_note_conversation_path(@conversation), params: { note: { body: body } }, as: :json
    assert_response :success
    assert_equal true, response.parsed_body['saved']
  end
end
