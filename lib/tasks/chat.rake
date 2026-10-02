namespace :chat do
  desc 'Publish due mutual reviews and deliver batched unread-message notifications'
  task maintenance: :environment do
    ChatMaintenance.run
  end
end
