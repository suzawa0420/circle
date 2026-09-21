root_path = File.expand_path('../../', __FILE__)

# This instance has two vCPUs. Keeping the default below the CPU count's
# high-concurrency threshold prevents request workers from exhausting
# Lightsail burst capacity; it can be overridden per server when measured.
worker_processes ENV.fetch("UNICORN_WORKERS", 4).to_i

working_directory root_path

pid "#{root_path}/tmp/pids/unicorn.pid"

listen "#{root_path}/tmp/sockets/unicorn.sock"

stderr_path "#{root_path}/log/unicorn.stderr.log"

stdout_path "#{root_path}/log/unicorn.stdout.log"

timeout 30

preload_app true

GC.respond_to?(:copy_on_write_friendly=) && GC.copy_on_write_friendly = true

check_client_connection false

run_once = true

before_fork do |server, worker|
    defined?(ActiveRecord::Base) &&
          ActiveRecord::Base.connection.disconnect!

      if run_once
            run_once = false # prevent from firing again
              end

        old_pid = "#{server.config[:pid]}.oldbin"
          if File.exist?(old_pid) && server.pid != old_pid
                begin
                        sig = (worker.nr + 1) >= server.worker_processes ? :QUIT : :TTOU
                              Process.kill(sig, File.read(old_pid).to_i)
                                  rescue Errno::ENOENT, Errno::ESRCH => e
                                          logger.error e
                                              end
                  end
end

after_fork do |_server, _worker|
    defined?(ActiveRecord::Base) && ActiveRecord::Base.establish_connection
end
