require 'test_helper'
require_relative '../support/chat_records'

class ChatMessageReactionsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords
  include ActionMailer::TestHelper

  setup do
    create_chat_records
    @message = @conversation.chat_messages.find_by!(sender_role: 'member')
    sign_in @owner
  end

  test 'create change retry and remove never send mail or change message conversation acceptance or unread state' do
    baseline = [@conversation.reload.attributes, @message.attributes, ChatMessage.count]
    %w[understood understood thanks checked like excited].each do |key|
      assert_no_emails do
        assert_no_enqueued_emails { react(key) }
      end
      assert_response :success
      assert_equal 1, @message.chat_message_reactions.count
      assert_equal key, @message.chat_message_reactions.sole.key
      assert_equal baseline, [@conversation.reload.attributes, @message.reload.attributes, ChatMessage.count]
    end
    2.times do
      assert_no_emails { assert_no_enqueued_emails { react('') } }
      assert_response :success
      assert_empty @message.chat_message_reactions
      assert_equal baseline, [@conversation.reload.attributes, @message.reload.attributes, ChatMessage.count]
    end
    assert_nil @conversation.accepted_at
  end

  test 'both sides have independent reactions with fixed options and polling refresh' do
    react('thanks', extra: { member_id: @other_member.id, admin_user_id: @other_member.id })
    assert_equal @owner.id, @message.chat_message_reactions.sole.admin_user_id
    get conversation_path(@conversation)
    assert_select "#chat-reactions-#{@message.id} summary", text: 'リアクション'
    assert_select "#chat-reactions-#{@message.id} button[aria-pressed=true]", text: '🙏ありがとうございます'
    assert_select "#chat-reactions-#{@message.id} form button[type=submit]", count: 5
    get messages_conversation_path(@conversation), as: :json
    initial = response.parsed_body['history_version']
    sign_out @owner
    sign_in @member
    react('like')
    assert_response :success
    assert_equal 2, @message.chat_message_reactions.count
    get messages_conversation_path(@conversation), as: :json
    assert_not_equal initial, response.parsed_body['history_version']
    assert_includes response.parsed_body['html'], 'いいですね'
    assert_includes response.parsed_body['html'], 'ありがとうございます'
    react('')
    assert_equal [@owner.id], @message.chat_message_reactions.pluck(:admin_user_id)
  end

  test 'same choice in rendered selector submits removal and different choice submits desired value' do
    react('checked')
    html = Nokogiri::HTML.fragment(response.parsed_body.fetch('html'))
    assert_equal '', html.at('button[aria-pressed=true]')['value']
    assert_equal 'thanks', html.css('button[type=submit]').find { |button| button.text.include?('ありがとうございます') }['value']
  end

  test 'invalid and missing choices do not write' do
    react('<script>')
    assert_response :unprocessable_entity
    assert_empty @message.chat_message_reactions
    assert_raises(ActionController::ParameterMissing) do
      put reaction_conversation_path(@conversation, message_id: @message.id), params: { reaction: { unexpected: 'thanks' } }, as: :json
    end
  end

  test 'unrelated member owner and anonymous visitors cannot read or mutate reactions' do
    react('thanks')
    sign_out @owner
    other_owner = AdminUser.create!(email: 'unrelated-reaction@example.test', password: 'test-password-123', email_verified_at: Time.current)
    other_circle = @circle.dup
    other_circle.assign_attributes(name: '別の主催者の検証', admin_user: other_owner)
    other_circle.save!
    [@other_member, other_owner].each do |outsider|
      sign_in outsider
      assert_raises(ActiveRecord::RecordNotFound, "outsider #{outsider.class}") { react('like') }
      assert_raises(ActiveRecord::RecordNotFound) { get messages_conversation_path(@conversation), as: :json }
      assert_raises(ActiveRecord::RecordNotFound) { get conversation_path(@conversation) }
      sign_out outsider
    end
    react('like')
    assert_response :redirect
    assert_equal 'thanks', @message.chat_message_reactions.sole.key
  end

  test 'a message from another conversation cannot be substituted' do
    other = Conversation.for_member!(@circle, @other_member)
    message = other.send_message!('member', '別の会話です。')
    assert_raises(ActiveRecord::RecordNotFound) { react('thanks', message: message) }
    assert_equal 0, ChatMessageReaction.count
  end

  test 'blocked deleted automatic and undelivered messages reject reactions and conceal existing badges' do
    react('thanks')
    @conversation.update!(member_blocked: true)
    react('like')
    assert_response :unprocessable_entity
    get conversation_path(@conversation)
    assert_select '.chat-reactions__badge, .chat-reactions__picker', count: 0
    @conversation.update!(member_blocked: false)
    [{ deleted_at: Time.current }, { moderation_status: 'held' }, { moderation_status: 'spam' }, { sender_role: 'system' }].each do |attributes|
      @message.update_columns(deleted_at: nil, moderation_status: 'delivered', sender_role: 'member')
      @message.update_columns(attributes)
      react('like')
      assert_response :unprocessable_entity
      get messages_conversation_path(@conversation), as: :json
      refute_includes response.parsed_body['html'], 'chat-reactions__badge'
    end
    assert_equal 'thanks', @message.chat_message_reactions.sole.key
  end

  test 'suspended or unverified actors cannot react and suspended peer hides reactions' do
    @owner.update!(suspended_at: Time.current)
    react('thanks')
    assert_response :redirect
    @owner.update!(suspended_at: nil, email_verified_at: nil)
    react('thanks')
    assert_redirected_to admin_user_email_verification_path
    @owner.update!(email_verified_at: Time.current)
    @member.update!(suspended_at: Time.current)
    react('thanks')
    assert_response :unprocessable_entity
    assert_empty @message.chat_message_reactions
  end

  test 'CSRF is required and valid per-form token works' do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    assert_raises(ActionController::InvalidAuthenticityToken) { react('thanks') }
    get conversation_path(@conversation)
    form = css_select("#chat-reactions-#{@message.id} form").first
    token = form.at('input[name=authenticity_token]')['value']
    put reaction_conversation_path(@conversation, message_id: @message.id), params: { reaction: { key: 'thanks' } }, headers: { 'X-CSRF-Token' => token }, as: :json
    assert_response :success
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  test 'practice match actors use organizer account identity on both sides' do
    source_owner = AdminUser.create!(email: 'reaction-practice@example.test', password: 'test-password-123', email_verified_at: Time.current)
    source = @circle.dup
    source.assign_attributes(name: '練習試合の検証', admin_user: source_owner)
    source.save!
    @conversation = Conversation.for_circles!(@circle, source)
    @message = @conversation.send_message!('member', '練習試合をお願いします。')
    react('understood')
    assert_response :success
    sign_out @owner
    sign_in source_owner
    react('thanks')
    assert_response :success
    assert_equal [@owner.id, source_owner.id].sort, @message.chat_message_reactions.pluck(:admin_user_id).sort
    assert_empty @message.chat_message_reactions.where.not(member_id: nil)
  end

  test 'database rejects duplicate actor rows and invalid account or choice and cascades with the message' do
    react('thanks')
    assert_raises(ActiveRecord::RecordNotUnique) do
      ChatMessageReaction.transaction(requires_new: true) do
        @message.chat_message_reactions.create!(admin_user: @owner, key: 'like')
      end
    end
    [{ member_id: nil, admin_user_id: nil, key: 'thanks' }, { member_id: @member.id, admin_user_id: nil, key: 'invalid' }].each do |invalid|
      assert_raises(ActiveRecord::StatementInvalid) do
        ChatMessageReaction.transaction(requires_new: true) do
          ChatMessageReaction.insert_all!([invalid.merge(chat_message_id: @message.id, created_at: Time.current, updated_at: Time.current)])
        end
      end
    end
    assert_difference 'ChatMessageReaction.count', -1 do
      @message.destroy!
    end
  end

  private

  def sign_in(account)
    scope = account.is_a?(Member) ? :member : :admin_user
    post public_send("#{scope}_session_path"), params: { scope => { email: account.email, password: 'test-password-123' } }
    assert_response :redirect
  end

  def sign_out(account)
    scope = account.is_a?(Member) ? :member : :admin_user
    delete public_send("destroy_#{scope}_session_path")
  end

  def react(key, extra: {}, message: @message)
    put reaction_conversation_path(@conversation, message_id: message.id), params: { reaction: { key: key }.merge(extra) }, as: :json
  end
end
