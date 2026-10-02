require 'test_helper'
require_relative '../support/chat_records'
require_relative '../../db/migrate/20261003000000_remove_legacy_contact_score_penalties'

class LegacyContactScoreTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    @circle.update!(user_time: Time.current.to_s)
    @circle.schedules.create!(title: '週末の練習', venue: '体育館', day: (Date.current + 7).to_s)
    UserContact.create!(user: @circle, name: '参加希望者', mail: 'legacy@example.test',
                        message: '練習に参加できますか？', respond_check: 'NG')
  end

  test 'legacy no reply reports do not lower the score' do
    CircleScoreUpdater.new.refresh(@circle)
    assert_in_delta 0.1, @circle.cb_point
  end

  test 'only new messages incur a penalty and an owner reply restores the score' do
    @conversation.update!(respond_check: 'NG')
    @conversation.refresh_circle_score!
    assert_in_delta(-29.9, @circle.reload.cb_point)

    accept_conversation
    assert_nil @conversation.reload.respond_check
    assert_in_delta 0.1, @circle.reload.cb_point
  end

  test 'backfill removes stored legacy penalties while preserving new penalties and activity times' do
    @circle.update_columns(cb_point: -59.9)
    @conversation.update!(respond_check: 'NG')
    original_times = @circle.attributes.slice('updated_at', 'user_time', 'last_post')

    RemoveLegacyContactScorePenalties.new.up

    assert_in_delta(-29.9, @circle.reload.cb_point)
    assert_equal original_times, @circle.attributes.slice('updated_at', 'user_time', 'last_post')
    assert_equal 'NG', UserContact.where(user: @circle).sole.respond_check

    @owner.update!(check: 1)
    RemoveLegacyContactScorePenalties.new.up
    assert_equal(-100, @circle.reload.cb_point)

    @owner.update!(check: nil)
    @circle.update_columns(user_time: 2.years.ago.to_s)
    RemoveLegacyContactScorePenalties.new.up
    assert_equal 0, @circle.reload.cb_point
  end
end
