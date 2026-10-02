require 'test_helper'
require_relative '../support/chat_records'

class ConversationUrlsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    post member_session_path, params: { member: { email: @member.email, password: 'test-password-123' } }
  end

  test 'random identifiers are stable and used for pages, actions and email links' do
    identifier = @conversation.public_id
    assert_match(/\A[A-Za-z0-9]{24}\z/, identifier)
    assert_equal identifier, @conversation.to_param
    get conversation_path(@conversation)
    assert_response :success
    assert_select "form[action='#{message_conversation_path(@conversation)}']"
    post message_conversation_path(@conversation), params: { message: { body: 'ランダムURLから送信します。' } }
    assert_redirected_to conversation_path(@conversation)
    assert_equal identifier, @conversation.reload.public_id
    assert_includes ChatMailer.new_messages(@conversation, 'member').body.decoded, "/conversations/#{identifier}"
    get "/conversations/#{@conversation.id}"
    assert_redirected_to conversation_path(@conversation)
  end

  test 'knowing another conversations identifier does not grant access' do
    other = Conversation.for_member!(@circle, @other_member)
    assert_not_equal @conversation.public_id, other.public_id
    assert_raises(ActiveRecord::RecordNotFound) { get conversation_path(other) }
    assert_raises(ActiveRecord::RecordNotFound) { get "/conversations/#{other.id}" }
  end
end
