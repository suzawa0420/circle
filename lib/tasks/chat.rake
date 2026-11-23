namespace :chat do
  desc 'Wake on committed unread-message schedules and deliver eligible notifications'
  task notify: :environment do
    stopping = false
    %w[TERM INT].each { |signal| Signal.trap(signal) { stopping = true } }
    ready = lambda do
      if ENV['NOTIFY_SOCKET'].present? && !system('/usr/bin/systemd-notify', '--ready')
        abort 'Could not report chat listener readiness to systemd'
      end
    end
    ChatNotificationWorker.new.run(stopping: -> { stopping }, ready: ready)
  end

  desc 'Publish due mutual reviews and deliver batched unread-message notifications'
  task maintenance: :environment do
    ChatMaintenance.run
  end
end
