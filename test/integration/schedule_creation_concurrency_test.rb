require 'test_helper'
require_relative '../support/chat_records'

class ScheduleCreationConcurrencyTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  self.use_transactional_tests = false
  include ChatRecords

  setup do
    create_chat_records
    @source = @circle.schedules.create!(day: '2026-11-07', title: '週末の練習', venue: '体育館')
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

  test 'concurrent submissions of the weekly copy return the same schedule' do
    sessions = 2.times.map do
      open_session.tap do |session|
        session.post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
        assert_equal 302, session.response.status
      end
    end
    sessions.first.get new_user_schedule_path(@circle), params: { copy: @source.id, copy_mode: 'next_week' }
    key = Nokogiri::HTML(sessions.first.response.body).at_css('input[name="schedule_creation_key"]')['value']
    ready, start = Queue.new, Queue.new
    assert_difference 'Schedule.count', 1 do
      threads = sessions.map do |session|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            start.pop
            session.post user_schedules_path(@circle), params: { copy: @source.id,
              schedule_creation_key: key, schedule: { day: '2026-11-14', title: @source.title, venue: @source.venue } }
            [session.response.status, session.response.location]
          end
        end
      end
      2.times { ready.pop }
      2.times { start << true }
      results = threads.map(&:value)
      assert results.all? { |status, _| status == 302 }
      assert_equal 1, results.map(&:last).uniq.size
    end
    created = @circle.schedules.find_by!(creation_key: key)
    assert_equal '2026-11-14', created.day
    assert_equal 1, @circle.schedules.where(day: '2026-11-14').count
  end

  test 'database rejects duplicate keys for a circle' do
    key = SecureRandom.uuid
    @source.update!(creation_key: key)
    assert_raises ActiveRecord::RecordNotUnique do
      @circle.schedules.create!(day: '2026-11-14', title: '重複', venue: '体育館', creation_key: key)
    end
  end
end
