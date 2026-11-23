# One supervised process on server4. LISTEN must precede the first scan to avoid
# missing a committed wake during startup. The periodic timer remains independent.
class ChatNotificationWorker
  MIN_WAIT = 0.05
  IDLE_RESCAN_SECONDS = 15
  FAILURE_BACKOFF_SECONDS = 15

  def run(stopping: -> { false })
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      connection.execute("LISTEN #{ChatNotificationWake::CHANNEL}")
      listener = connection.raw_connection
      begin
        until stopping.call
          # No Rails request executor, and avoid caching future/previous due queries.
          wait = ActiveRecord::Base.uncached { process_due }
          if wait
            listener.wait_for_notify(wait) unless stopping.call
          else
            back_off(listener, stopping)
          end
        end
      ensure
        listener.exec("UNLISTEN #{ChatNotificationWake::CHANNEL}") unless listener.finished?
      end
    end
  end

  private

  def back_off(listener, stopping)
    retry_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + FAILURE_BACKOFF_SECONDS
    until stopping.call
      remaining = retry_at - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      break unless remaining.positive?
      listener.wait_for_notify(remaining)
    end
  end

  def process_due
    participant_conversations = Conversation.where(source_user_id: nil)
    if ChatMaintenance.deliver_due_messages(participant_conversations).positive?
      # Let the existing timer also retry. A provider failure must not spin.
      return nil
    end

    next_due = Conversation::ROLES.filter_map do |role|
      column = "#{role}_notification_due_at"
      participant_conversations.where.not(column => nil).order(column).pick(column)
    end.min
    return IDLE_RESCAN_SECONDS unless next_due

    (next_due - Time.current).clamp(MIN_WAIT, IDLE_RESCAN_SECONDS)
  end
end
