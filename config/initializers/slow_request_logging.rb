slow_request_threshold_ms = ENV.fetch("SLOW_REQUEST_THRESHOLD_MS", "500").to_f

ActiveSupport::Notifications.subscribe("process_action.action_controller") do |_name, started, finished, _id, payload|
  duration_ms = (finished - started) * 1_000
  next if duration_ms < slow_request_threshold_ms

  Rails.logger.warn(
    format(
      "[Slow Request] %<controller>s#%<action>s status=%<status>s duration=%<duration>.1fms db=%<db>.1fms view=%<view>.1fms",
      controller: payload[:controller],
      action: payload[:action],
      status: payload[:status] || 500,
      duration: duration_ms,
      db: payload[:db_runtime].to_f,
      view: payload[:view_runtime].to_f
    )
  )
end
