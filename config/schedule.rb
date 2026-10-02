if @environment.to_sym == :production
  every 1.day, at: '10:00 am' do
    rake 'sitemap:refresh'
  end
end
# Production chat maintenance uses circle-chat-maintenance.timer on server4.
# Do not also install a cron entry: both would process the same shared DB.
