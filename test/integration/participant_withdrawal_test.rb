require 'test_helper'
require_relative '../support/chat_records'

class ParticipantWithdrawalTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup { create_chat_records }

  def login
    post member_session_path, params: { member: { email: @member.email, password: 'test-password-123' } }
  end

  test 'help and account settings link to the participant confirmation screen' do
    get help_article_path('withdraw-member')
    assert_response :success
    assert_select "a[href='#{unsubscribe_member_path}']", text: '参加者の退会手続き'
    assert_select '.help-answer ol li', count: 3
    login
    [member_path(@member), edit_member_registration_path].each do |path|
      get path
      assert_select "a[href='#{unsubscribe_member_path}']"
    end
    get unsubscribe_member_path
    assert_response :success
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_select 'input[name=confirm_withdrawal][required]'
    assert_select "a[href='#{member_path(@member)}']", text: '退会せずマイページへ戻る'
    assert_select '.participant-card', text: /主催者側からも閲覧できなくなります/
    assert Member.exists?(@member.id)
  end

  test 'anonymous visitors log in and return to confirmation instead of registration' do
    get unsubscribe_member_path
    assert_redirected_to new_member_session_path
    login
    assert_redirected_to unsubscribe_member_path
    follow_redirect!
    assert_response :success
  end

  test 'anonymous and organizer sessions cannot delete a participant' do
    assert_no_difference 'Member.count' do
      delete unsubscribe_member_path, params: { confirm_withdrawal: '1', id: @member.id }
    end
    assert_redirected_to new_member_session_path
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    assert_no_difference 'Member.count' do
      delete unsubscribe_member_path, params: { confirm_withdrawal: '1', id: @member.id }
    end
    assert_redirected_to new_member_session_path
  end

  test 'deletion requires confirmation and the alternate devise endpoint cannot bypass it' do
    login
    assert_no_difference 'Member.count' do
      delete unsubscribe_member_path
      assert_response :unprocessable_entity
      delete member_registration_path
      assert_redirected_to unsubscribe_member_path
      get member_path(@member)
      assert_response :success
    end
  end

  test 'confirmed withdrawal only deletes the signed in participant and dependent chat data' do
    login
    @member.bookmarks.create!(user: @circle)
    @member.events = [@circle.event]
    assert_no_difference 'ActionMailer::Base.deliveries.size' do
      assert_difference 'Member.count', -1 do
        delete unsubscribe_member_path, params: { confirm_withdrawal: '1', id: @other_member.id, member_id: @other_member.id }
      end
    end
    assert_redirected_to root_path
    assert_not Conversation.exists?(@conversation.id)
    assert_not ChatMessage.where(conversation_id: @conversation.id).exists?
    assert_not Bookmark.where(member_id: @member.id).exists?
    assert_not MembersEvent.where(member_id: @member.id).exists?
    assert Member.exists?(@other_member.id)
    assert AdminUser.exists?(@owner.id)
    assert User.exists?(@circle.id)
    get unsubscribe_member_path
    assert_redirected_to new_member_session_path
  end

  test 'retained application records prevent deletion safely without changing retention policy' do
    Application.create!(member: @member, applied_at: Time.current)
    login
    assert_no_difference ['Member.count', 'Conversation.count', 'ChatMessage.count', 'Application.count'] do
      delete unsubscribe_member_path, params: { confirm_withdrawal: '1' }
    end
    assert_response :unprocessable_entity
    assert_includes response.body, 'アカウントは削除されていません'
    assert_select "a[href='#{new_support_request_path(category: 'account', article_id: 'withdraw-member')}']"
  end

  test 'csrf prevents confirmed deletion without an authenticity token' do
    login
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    assert_no_difference 'Member.count' do
      assert_raises(ActionController::InvalidAuthenticityToken) do
        delete unsubscribe_member_path, params: { confirm_withdrawal: '1' }
      end
    end
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end
end
