require 'test_helper'
require_relative '../support/chat_records'

class ConversationTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  include ChatRecords
  setup { create_chat_records }

  test 'one conversation per circle and member; first owner reply starts an immutable fourteen day deadline' do
    assert_equal @conversation, Conversation.for_member!(@circle, @member)
    assert_nil @conversation.accepted_at
    assert_raises(Conversation::NotAllowed) { @conversation.submit_review!('member', member_evaluation) }
    accept_conversation
    assert_in_delta 14.days, @conversation.review_deadline - @conversation.accepted_at, 1
    deadline = @conversation.review_deadline
    travel 1.day do
      @conversation.send_message!('owner', 'その後いかがでしょうか？')
      assert_equal deadline, @conversation.reload.review_deadline
    end
  end

  test 'reviews are blind until both submit, then combined with legacy reviews and publicly scored' do
    Review.create!(user: @circle, review: 0, comment: '以前からある口コミです。')
    accept_conversation
    @conversation.submit_review!('member', member_evaluation)
    assert_equal 1, @circle.reviews.count
    assert_empty @member.received_conversation_reviews
    assert_nil @conversation.reviews_published_at
    @conversation.submit_review!('owner', owner_evaluation)
    assert @conversation.reload.reviews_published_at
    assert_equal 2, @circle.reviews.count
    assert_equal 2.5, @circle.reload.review_score.to_f
    assert_equal 1, @member.received_conversation_reviews.count
    assert_equal 0, @member.received_review_score
    assert_raises(Conversation::NotAllowed) { @conversation.submit_review!('member', member_evaluation.merge(score: 0)) }
    @conversation.publish_reviews!
    assert_equal 2, @circle.reviews.count
  end

  test 'a single review publishes at deadline and the missing author can no longer submit' do
    accept_conversation
    @conversation.submit_review!('member', member_evaluation)
    travel_to @conversation.review_deadline + 1.second do
      ChatMaintenance.run
      assert_equal 1, @circle.reviews.count
      assert_raises(Conversation::NotAllowed) { @conversation.submit_review!('owner', owner_evaluation) }
    end
  end

  test 'unpublished evaluation can be edited deleted and resubmitted' do
    accept_conversation
    @conversation.submit_review!('member', member_evaluation)
    @conversation.submit_review!('member', member_evaluation.merge(comment: '投稿内容を訂正しました。'))
    assert_equal 1, @conversation.conversation_reviews.count
    @conversation.delete_review!('member')
    assert_empty @conversation.conversation_reviews
    @conversation.submit_review!('member', member_evaluation)
    assert_equal 1, @conversation.conversation_reviews.count
  end

  test 'deleting a published review removes its score, preserves peer review and permanently consumes entitlement' do
    accept_conversation
    @conversation.submit_review!('member', member_evaluation)
    @conversation.submit_review!('owner', owner_evaluation)
    @conversation.delete_review!('member')
    assert_empty @circle.reviews
    assert_equal 0, @circle.reload.review_score.to_f
    assert_equal 1, @member.received_conversation_reviews.count
    assert_raises(Conversation::NotAllowed) { @conversation.submit_review!('member', member_evaluation) }
    @conversation.delete_review!('owner')
    assert_empty @member.received_conversation_reviews
    assert_equal 2, @conversation.conversation_reviews.count
  end

  test 'delete after deadline first publishes both state and keeps the public tombstone' do
    accept_conversation
    @conversation.submit_review!('owner', owner_evaluation)
    travel_to @conversation.review_deadline + 1.second do
      @conversation.delete_review!('owner')
      assert @conversation.conversation_reviews.first.deleted_at
      assert @conversation.reviews_published_at
    end
  end

  test 'blocking stops both senders but not reviews or read history' do
    accept_conversation
    @conversation.update!(owner_blocked: true)
    %w[owner member].each do |role|
      assert_raises(Conversation::NotAllowed) { @conversation.send_message!(role, 'メッセージです。') }
    end
    @conversation.submit_review!('member', member_evaluation)
    @conversation.submit_review!('owner', owner_evaluation)
    assert_equal 2, @conversation.chat_messages.where.not(sender_role: 'system').count
    assert @conversation.reviews_published_at
  end

  test 'email verification resets on changed email and old verification purpose changes' do
    old_purpose = @member.email_verification_purpose
    @member.update!(email: 'changed@example.test')
    assert_not @member.email_verified?
    assert_not_equal old_purpose, @member.email_verification_purpose
    assert_raises(Conversation::NotAllowed) { @conversation.send_message!('member', '未認証です。') }
  end

  test 'notifications are batched contain no message text and cancel when read' do
    ActionMailer::Base.deliveries.clear
    @conversation.send_message!('member', 'こちらは通知メールに含めない秘密の文章です。')
    travel 6.minutes do
      ChatMaintenance.run
      assert_equal 1, ActionMailer::Base.deliveries.size
      mail = ActionMailer::Base.deliveries.last
      assert_not_includes mail.body.to_s, '秘密の文章'
      assert_includes mail.body.to_s, "/conversations/#{@conversation.public_id}"
      ChatMaintenance.run
      assert_equal 1, ActionMailer::Base.deliveries.size
      accept_conversation
      @conversation.mark_read!('member', through: @conversation.chat_messages.maximum(:id))
      travel 6.minutes
      ChatMaintenance.run
      assert_equal 1, ActionMailer::Base.deliveries.size
    end
  end

  test 'reading an earlier page cannot mark a newer concurrent message read' do
    seen_id = @conversation.chat_messages.maximum(:id)
    @conversation.send_message!('member', '新しいメッセージです。')
    @conversation.mark_read!('owner', through: seen_id)
    assert @conversation.owner_notification_due_at
    assert_equal seen_id, @conversation.owner_read_message_id
  end

  test 'legacy reviews prevent duplicate member evaluations but owner can evaluate at deadline' do
    Review.create!(user: @circle, member: @member, review: 1, comment: '以前の投稿を残しています。')
    accept_conversation
    assert_raises(Conversation::NotAllowed) { @conversation.submit_review!('member', member_evaluation) }
    @conversation.submit_review!('owner', owner_evaluation)
    travel_to @conversation.review_deadline + 1.second do
      @conversation.publish_reviews!
      assert_equal 1, @member.received_conversation_reviews.count
      assert_equal 1, @circle.reviews.count
    end
  end

  test 'invalid comments cannot partially publish evaluations' do
    accept_conversation
    @conversation.submit_review!('member', member_evaluation)
    assert_raises(ActiveRecord::RecordInvalid) { @conversation.submit_review!('owner', owner_evaluation.merge(comment: '短')) }
    assert_nil @conversation.reload.reviews_published_at
    assert_empty @circle.reviews
  end
  test 'message rate limit rejects a burst without losing existing messages' do
    9.times { @conversation.send_message!('member', '追加のメッセージです。') }
    assert_raises(Conversation::NotAllowed) { @conversation.send_message!('member', '送信上限を超えています。') }
    assert_equal 10, @conversation.chat_messages.where.not(sender_role: 'system').count
  end

  test 'blocked unread messages do not trigger email notifications' do
    ActionMailer::Base.deliveries.clear
    @conversation.update!(owner_blocked: true)
    travel 6.minutes do
      ChatMaintenance.run
      assert_empty ActionMailer::Base.deliveries
    end
  end

  test 'a legacy entitlement placeholder does not allow an owner to manufacture an inquiry' do
    placeholder = Conversation.for_member!(@circle, @other_member)
    assert_raises(Conversation::NotAllowed) { placeholder.send_message!('owner', '問い合わせがないのに評価します。') }
    assert_nil placeholder.reload.accepted_at
  end

end
