if @environment.to_sym == :production
  every 1.day, at: '10:00 am' do
    rake 'sitemap:refresh'
  end
end
every 1.minute do
  rake 'chat:maintenance'
end
