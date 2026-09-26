# AL2023 only. Keep the existing Nginx socket path during this transition.
root = File.expand_path('../..', __dir__)
directory root
environment 'production'
bind "unix://#{root}/tmp/sockets/unicorn.sock?umask=0007"
pidfile "#{root}/tmp/pids/puma.pid"
workers 8
threads 1, 1
preload_app!
worker_timeout 60
worker_shutdown_timeout 30

before_fork do
  ActiveRecord::Base.connection_pool.disconnect! if defined?(ActiveRecord::Base)
end

before_worker_boot do
  ActiveRecord::Base.establish_connection if defined?(ActiveRecord::Base)
end
