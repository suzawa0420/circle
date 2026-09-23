require Rails.root.join('lib/abuse_counter_store')
require Rails.root.join('lib/abuse_protection')

AbuseProtection.configure(
  store: AbuseCounterStore.new(Rails.root.join('tmp/abuse_counters'), logger: Rails.logger),
  logger: Rails.logger
)
