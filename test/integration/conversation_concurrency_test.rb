require 'test_helper'
require_relative '../support/chat_records'

class ConversationConcurrencyTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  self.use_transactional_tests = false
  include ChatRecords

  setup do
    skip 'PostgreSQL row locks required' unless ActiveRecord::Base.connection.adapter_name == 'PostgreSQL'
    create_chat_records
  end

  teardown do
    if @circle
      event, category, prefecture = @circle.event, @circle.category, @circle.prefecture
      @circle.destroy!
      @owner.destroy!
      @member.destroy!
      @other_member.destroy!
      event.destroy!
      category.destroy!
      prefecture.destroy!
    end
  end

  test 'simultaneous evaluations publish exactly one circle review and two immutable evaluations' do
    accept_conversation
    results = concurrently do |i|
      Conversation.find(@conversation.id).submit_review!(i.zero? ? 'member' : 'owner', i.zero? ? member_evaluation : owner_evaluation)
    end
    assert results.all? { |result| result.is_a?(ConversationReview) }
    assert @conversation.reload.reviews_published_at
    assert_equal 2, @conversation.conversation_reviews.count
    assert_equal 1, @circle.reviews.count
    assert_equal 1, @member.received_conversation_reviews.count
  end

  test 'simultaneous contact creation cannot create duplicate conversation pairs' do
    results = concurrently { Conversation.for_member!(@circle, @other_member) }
    assert_equal 1, results.map(&:id).uniq.count
    assert_equal 1, Conversation.where(user: @circle, member: @other_member).count
  end

  test 'simultaneous approvals release only once and retain unread state' do
    held = @conversation.send_message!('member', '性愛預約服務')
    results = concurrently { ChatMessage.find(held.id).moderate!('approve') }
    assert_equal [false, true], results.sort_by { |v| v ? 1 : 0 }
    assert_equal 'approved', held.reload.moderation_status
    assert held.released_at
    assert_nil held.recipient_read_at
    assert @conversation.reload.owner_notification_due_at
  end

  test 'opposite organizers starting simultaneously share one conversation' do
    source_owner = AdminUser.create!(email: 'concurrent-practice@example.test', password: 'test-password-123', email_verified_at: Time.current)
    source = @circle.dup
    source.admin_user = source_owner
    source.save!
    results = concurrently do |i|
      i.zero? ? Conversation.for_circles!(@circle, source) : Conversation.for_circles!(source, @circle)
    end
    assert_equal 1, results.map(&:id).uniq.count
    assert_equal 1, Conversation.where(user: @circle, source_user: source).or(Conversation.where(user: source, source_user: @circle)).count
  ensure
    source&.destroy!
    source_owner&.destroy!
  end

  private
  test 'simultaneous reactions converge without duplicate actor rows or message side effects' do
    message = @conversation.chat_messages.find_by!(sender_role: 'member')
    before = @conversation.reload.attributes
    concurrently { ChatMessage.find(message.id).set_reaction!('owner', 'thanks') }
    assert_equal 1, message.chat_message_reactions.count
    assert_equal 'thanks', message.chat_message_reactions.sole.key
    concurrently { |i| ChatMessage.find(message.id).set_reaction!('owner', i.zero? ? 'checked' : 'like') }
    assert_equal 1, message.chat_message_reactions.count
    assert_includes %w[checked like], message.chat_message_reactions.sole.key
    concurrently { ChatMessage.find(message.id).set_reaction!('owner', '') }
    assert_empty message.chat_message_reactions
    concurrently { |i| ChatMessage.find(message.id).set_reaction!(i.zero? ? 'member' : 'owner', 'thanks') }
    assert_equal 2, message.chat_message_reactions.count
    assert_equal before, @conversation.reload.attributes
  end

  def concurrently
    ready, start = Queue.new, Queue.new
    threads = 2.times.map do |i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          yield i
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    threads.map(&:value)
  end
end
