require 'test_helper'
require_relative '../support/chat_records'

class ConversationNotesTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup { create_chat_records }

  test 'each participant has a private note with no message or inbox ordering changes' do
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

  private

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
