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

  private
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
