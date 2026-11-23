# Best-effort hint only. The due time in PostgreSQL is durable and the timer is the fallback.
class ChatNotificationWake
  CHANNEL = 'circle_chat_notification_wake'.freeze

  def self.signal
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      connection.execute("SELECT pg_notify('#{CHANNEL}', '')")
    end
  rescue StandardError => error
    Rails.logger.warn("[ChatNotificationWake] signal_failed error_class=#{error.class.name}")
  end
end
