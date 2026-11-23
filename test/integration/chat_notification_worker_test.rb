require 'test_helper'
require 'minitest/mock'
require 'timeout'
require_relative '../support/chat_records'

class ChatNotificationWorkerTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  self.use_transactional_tests = false
  include ChatRecords

  setup do
    skip 'PostgreSQL LISTEN and row locks required' unless ActiveRecord::Base.connection.adapter_name == 'PostgreSQL'
    create_chat_records
    @conversation.mark_read!('owner', through: @conversation.chat_messages.maximum(:id))
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

  test 'notification waits for the outer transaction to commit and is not sent on rollback' do
    connection = ActiveRecord::Base.connection_pool.checkout
    connection.execute("LISTEN #{ChatNotificationWake::CHANNEL}")
    listener = connection.raw_connection
    @conversation.transaction do
      accept_conversation
      assert_nil listener.wait_for_notify(0.05)
      raise ActiveRecord::Rollback
    end
    assert_nil listener.wait_for_notify(0.05)
    assert_nil @conversation.reload.member_notification_due_at

    @conversation.transaction do
      accept_conversation
      assert_nil listener.wait_for_notify(0.05)
    end
    assert_equal ChatNotificationWake::CHANNEL, listener.wait_for_notify(1)
    assert_in_delta 7, @conversation.reload.member_notification_due_at - Time.current, 1
  ensure
    if connection
      connection.execute("UNLISTEN #{ChatNotificationWake::CHANNEL}")
      ActiveRecord::Base.connection_pool.checkin(connection)
    end
  end

  test 'real listener and periodic fallback contend without sending duplicate mail' do
    delivered = Queue.new
    fake_mail = Object.new
    fake_mail.define_singleton_method(:deliver_now) do
      delivered << Process.clock_gettime(Process::CLOCK_MONOTONIC)
      sleep 0.1
    end
    stopped = Queue.new
    readiness = Queue.new
    worker = nil

    ChatMailer.stub(:new_messages, fake_mail) do
      worker = Thread.new do
        ChatNotificationWorker.new.run(stopping: -> { !stopped.empty? }, ready: -> { readiness << true })
      end
      assert Timeout.timeout(5) { readiness.pop }
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      accept_conversation
      due = @conversation.reload.member_notification_due_at
      assert_in_delta 7, due - Time.current, 1
      timestamp = Timeout.timeout(14) { delivered.pop }
      fallback = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { ChatMaintenance.run }
      end
      assert_operator timestamp - started, :>=, 6.8
      assert_operator timestamp - started, :<, 13
      fallback.value
      ChatMaintenance.run
      assert_empty delivered
      assert_nil @conversation.reload.member_notification_due_at
      assert @conversation.member_notified_at
    ensure
      stopped << true
      ChatNotificationWake.signal
      worker&.value
    end
  end

  test 'a lost listener session exits so the supervisor can restart and discover committed pending work' do
    ready = Queue.new
    first = Thread.new do
      Thread.current.report_on_exception = false
      ChatNotificationWorker.new.run(ready: -> {
        pool = ActiveRecord::Base.connection_pool
        pid = pool.with_connection { |connection| connection.select_value('SELECT pg_backend_pid()') }
        ready << pid
      })
    end
    pid = Timeout.timeout(5) { ready.pop }
    assert_equal true, ActiveRecord::Base.connection.select_value("SELECT pg_terminate_backend(#{Integer(pid)})")
    assert_raises(PG::Error, ActiveRecord::ConnectionNotEstablished) { Timeout.timeout(5) { first.value } }

    ChatNotificationWake.stub(:signal, -> { nil }) { accept_conversation }
    @conversation.update!(member_notification_due_at: 1.second.ago)
    delivered = Queue.new
    mailer = Object.new
    mailer.define_singleton_method(:deliver_now) { delivered << true }
    ChatMailer.stub(:new_messages, mailer) do
      ChatNotificationWorker.new.run(stopping: -> { !delivered.empty? })
    end
    assert_equal true, delivered.pop
    assert_nil @conversation.reload.member_notification_due_at
  end

  test 'a dropped wake or transient SMTP error leaves an existing due row for periodic fallback' do
    ChatNotificationWake.stub(:signal, -> { nil }) { accept_conversation }
    original_due = @conversation.reload.member_notification_due_at
    assert original_due
    travel_to original_due + 1.second do
      failing_mail = Object.new
      failing_mail.define_singleton_method(:deliver_now) { raise IOError, 'synthetic' }
      ChatMailer.stub(:new_messages, failing_mail) do
        assert_raises(ChatMaintenance::DeliveryFailed) { ChatMaintenance.run }
      end
      assert_equal original_due, @conversation.reload.member_notification_due_at
      assert_nil @conversation.member_notified_at

      assert_difference 'ActionMailer::Base.deliveries.size', 1 do
        ChatMaintenance.run
        ChatMaintenance.run
      end
      assert_nil @conversation.reload.member_notification_due_at
    end
  end
end
