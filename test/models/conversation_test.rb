require 'test_helper'
require 'minitest/mock'
require_relative '../support/chat_records'

class ConversationTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  include ChatRecords
  setup { create_chat_records }

  test 'one conversation per circle and member; first owner reply starts an immutable thirty day deadline' do
    assert_equal @conversation, Conversation.for_member!(@circle, @member)
    assert_nil @conversation.accepted_at
    assert_raises(Conversation::NotAllowed) { @conversation.submit_review!('member', member_evaluation) }
    accept_conversation
    assert_in_delta 30.days, @conversation.review_deadline - @conversation.accepted_at, 1
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

  test 'review prompts start seven days after reply and each side can postpone or dismiss independently' do
    assert_not @conversation.review_prompt_due?('member')
    accept_conversation
    travel_to @conversation.accepted_at + 7.days + 1.second do
      assert @conversation.review_prompt_due?('member')
      assert @conversation.review_prompt_due?('owner')
      @conversation.update_review_prompt!('member', 'later')
      @conversation.update_review_prompt!('owner', 'dismiss')
      assert_not @conversation.review_prompt_due?('member')
      assert_not @conversation.review_prompt_due?('owner')
      travel 7.days
      assert @conversation.reload.review_prompt_due?('member')
      assert_not @conversation.review_prompt_due?('owner')
      # Opting out of reminders does not remove the ability to submit.
      @conversation.submit_review!('owner', owner_evaluation)
      assert @conversation.review_prompt_due?('member')
      @conversation.submit_review!('member', member_evaluation)
      assert_not @conversation.reload.review_prompt_due?('member')
    end
  end

  test 'prompts stop after own submission deadline suspension or legacy review' do
    accept_conversation
    travel 8.days do
      @conversation.submit_review!('member', member_evaluation)
      assert_not @conversation.review_prompt_due?('member')
      assert @conversation.review_prompt_due?('owner')
      @owner.update!(email_verified_at: nil)
      @conversation.reload
      assert_not @conversation.review_prompt_due?('owner')
      assert_raises(Conversation::NotAllowed) { @conversation.update_review_prompt!('owner', 'later') }
    end
    travel_to @conversation.review_deadline do
      assert_not @conversation.review_prompt_due?('owner')
    end
  end

  test 'legacy reviewers are not prompted and invalid reminder choices cannot update preferences' do
    accept_conversation
    travel 8.days do
      @conversation.update!(legacy_member_review: true)
      assert_not @conversation.review_prompt_due?('member')
      assert @conversation.review_prompt_due?('owner')
      assert_raises(Conversation::NotAllowed) { @conversation.update_review_prompt!('owner', 'invalid') }
      assert_nil @conversation.reload.owner_review_prompt_after
    end
  end

  test 'first peer review immediately invites only the missing side and keeps content private' do
    accept_conversation
    @conversation.update!(owner_review_prompt_after: 20.days.from_now)
    @conversation.submit_review!('member', member_evaluation)
    assert @conversation.owner_review_invited_at
    assert_nil @conversation.member_review_invited_at
    assert @conversation.review_prompt_due?('owner')
    assert @conversation.peer_review_waiting?('owner')
    assert_not @conversation.peer_review_waiting?('member')
    assert_not @conversation.review_prompt_due?('member')
    assert_empty @circle.reviews
    assert_empty @member.received_conversation_reviews
  end

  test 'owner review also immediately invites a member before seven days' do
    accept_conversation
    @conversation.submit_review!('owner', owner_evaluation)
    assert @conversation.review_prompt_due?('member')
    assert @conversation.peer_review_waiting?('member')
    assert_nil @conversation.owner_review_invited_at
    assert @conversation.member_review_invited_at
  end

  test 'review notification email goes to the missing side once and never includes score or comment' do
    accept_conversation
    @conversation.submit_review!('member', member_evaluation)
    due = @conversation.owner_review_notification_due_at
    ActionMailer::Base.deliveries.clear
    ChatMaintenance.deliver_review_invitation(@conversation, 'owner')
    assert_empty ActionMailer::Base.deliveries
    travel_to due + 1.second do
      2.times { ChatMaintenance.deliver_review_invitation(@conversation, 'owner') }
      mail = ActionMailer::Base.deliveries.sole
      assert_equal [@owner.email], mail.to
      assert_includes mail.subject, '口コミが届いています'
      assert_includes mail.body.decoded, 'あなたも口コミを投稿すると'
      assert_includes mail.body.decoded, "#{@conversation.public_id}#evaluation"
      assert_not_includes mail.body.decoded, member_evaluation[:comment]
      assert_not_includes mail.body.decoded, '良かった'
      assert_not_includes mail.body.decoded, '残念だった'
      assert @conversation.reload.owner_review_notified_at
      assert_nil @conversation.owner_review_notification_due_at
    end
  end

  test 'editing deleting and reposting cannot issue repeated invitations' do
    accept_conversation
    @conversation.submit_review!('member', member_evaluation)
    invited = @conversation.owner_review_invited_at
    due = @conversation.owner_review_notification_due_at
    @conversation.update_review_prompt!('owner', 'dismiss')
    @conversation.submit_review!('member', member_evaluation.merge(score: 0))
    @conversation.delete_review!('member')
    @conversation.submit_review!('member', member_evaluation)
    assert_equal invited, @conversation.owner_review_invited_at
    assert_equal due, @conversation.owner_review_notification_due_at
    assert @conversation.owner_review_prompt_dismissed
  end

  test 'both submissions before mail delivery cancel the pending invitation' do
    accept_conversation
    @conversation.submit_review!('owner', owner_evaluation)
    @conversation.submit_review!('member', member_evaluation)
    ActionMailer::Base.deliveries.clear
    travel 6.minutes do
      ChatMaintenance.deliver_review_invitation(@conversation, 'member')
      assert_empty ActionMailer::Base.deliveries
      assert_nil @conversation.reload.member_review_notification_due_at
      assert_not @conversation.peer_review_waiting?('member')
      assert @conversation.reviews_published_at
    end
  end

  test 'deleted peer review cancels invitation email' do
    accept_conversation
    @conversation.submit_review!('member', member_evaluation)
    @conversation.delete_review!('member')
    ActionMailer::Base.deliveries.clear
    travel 6.minutes do
      ChatMaintenance.deliver_review_invitation(@conversation, 'owner')
      assert_empty ActionMailer::Base.deliveries
      assert_nil @conversation.reload.owner_review_notification_due_at
    end
  end

  test 'blocking or declining prompts prevents the pending email' do
    accept_conversation
    @conversation.submit_review!('member', member_evaluation)
    ActionMailer::Base.deliveries.clear
    @conversation.update_review_prompt!('owner', 'later')
    travel 6.minutes do
      ChatMaintenance.deliver_review_invitation(@conversation, 'owner')
      assert_empty ActionMailer::Base.deliveries
      assert_nil @conversation.reload.owner_review_notification_due_at
      @conversation.update!(owner_review_notification_due_at: 1.minute.ago, owner_review_prompt_after: 1.minute.ago, member_blocked: true)
      ChatMaintenance.deliver_review_invitation(@conversation, 'owner')
      assert_empty ActionMailer::Base.deliveries
    end
  end

  test 'review mail failures keep their pending deadline for retry' do
    accept_conversation
    @conversation.submit_review!('member', member_evaluation)
    failing_mail = Object.new
    def failing_mail.deliver_now = raise('Synthetic delivery failure')
    travel 6.minutes do
      ChatMailer.stub(:review_received, failing_mail) do
        assert_raises(RuntimeError) { ChatMaintenance.deliver_review_invitation(@conversation, 'owner') }
      end
      assert @conversation.reload.owner_review_notification_due_at
      assert_nil @conversation.owner_review_notified_at
      ActionMailer::Base.deliveries.clear
      ChatMaintenance.run
      assert_equal 1, ActionMailer::Base.deliveries.count { |mail| mail.subject.include?('口コミが届いています') }
      assert @conversation.reload.owner_review_notified_at
    end
  end

  test 'editing a review from before notifications were introduced does not send an invitation' do
    accept_conversation
    @conversation.conversation_reviews.create!(member_evaluation.merge(author_role: 'member'))
    @conversation.submit_review!('member', member_evaluation.merge(comment: '以前の感想を更新しました。'))
    assert_nil @conversation.owner_review_invited_at
    assert_nil @conversation.owner_review_notification_due_at
  end

  test 'ineligible or expired recipients do not receive review invitation mail' do
    accept_conversation
    @conversation.submit_review!('owner', owner_evaluation)
    @member.update!(email_verified_at: nil)
    ActionMailer::Base.deliveries.clear
    travel 6.minutes do
      ChatMaintenance.deliver_review_invitation(@conversation.reload, 'member')
      assert_empty ActionMailer::Base.deliveries
      assert_nil @conversation.reload.member_review_notification_due_at
    end
    @member.update!(email_verified_at: Time.current)
    @conversation.update!(member_review_notification_due_at: 1.minute.ago)
    travel_to @conversation.review_deadline + 1.second do
      ChatMaintenance.deliver_review_invitation(@conversation, 'member')
      assert_empty ActionMailer::Base.deliveries
    end
  end

  test 'an earlier opt out remains respected when the peer submits a review' do
    accept_conversation
    @conversation.update!(owner_review_prompt_dismissed: true)
    @conversation.submit_review!('member', member_evaluation)
    assert @conversation.owner_review_invited_at
    assert_not @conversation.review_prompt_due?('owner')
    ActionMailer::Base.deliveries.clear
    travel 6.minutes do
      ChatMaintenance.deliver_review_invitation(@conversation, 'owner')
      assert_empty ActionMailer::Base.deliveries
    end
  end

  test 'maintenance can run during deployment before the review notification columns are visible' do
    accept_conversation
    @conversation.submit_review!('member', member_evaluation)
    old_columns = Conversation.column_names - ['member_review_notification_due_at']
    travel 6.minutes do
      ActionMailer::Base.deliveries.clear
      Conversation.stub(:column_names, old_columns) { ChatMaintenance.run }
      assert_not ActionMailer::Base.deliveries.any? { |mail| mail.subject.include?('口コミが届いています') }
      assert @conversation.reload.owner_review_notification_due_at
      ChatMaintenance.run
      assert_equal 1, ActionMailer::Base.deliveries.count { |mail| mail.subject.include?('口コミが届いています') }
    end
  end

end
