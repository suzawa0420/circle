namespace :chat do
  desc 'Wake on committed unread-message schedules and deliver eligible notifications'
  task notify: :environment do
    stopping = false
    %w[TERM INT].each { |signal| Signal.trap(signal) { stopping = true } }
    ChatNotificationWorker.new.run(stopping: -> { stopping })
  end

  desc 'Publish due mutual reviews and deliver batched unread-message notifications'
  task maintenance: :environment do
    ChatMaintenance.run
  end
end
