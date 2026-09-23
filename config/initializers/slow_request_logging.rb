# Only fixed controller/action identifiers and timings: never params, URLs or SQL.
# Production uses log_level=:error, so emit at that level without enabling
# verbose request logging (which can contain personal information).
ActiveSupport::Notifications.monotonic_subscribe('process_action.action_controller') do |_name, started, finished, _id, payload|
  duration_ms = (finished - started) * 1000
  next if duration_ms < 2000

  Rails.logger.error(format(
    '[Slow Request] %s#%s status=%s duration=%.1fms db=%.1fms view=%.1fms',
    payload[:controller], payload[:action], payload[:status] || 500,
    duration_ms, payload[:db_runtime].to_f, payload[:view_runtime].to_f
  ))
end
