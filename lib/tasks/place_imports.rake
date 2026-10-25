namespace :places do
  desc 'Collect official facility candidates; APPLY=1 registers up to LIMIT (default 5)'
  task discover: :environment do
    limit = Integer(ENV.fetch('LIMIT', '5'), 10)
    run = PlaceImports::Runner.new.call(apply: ENV['APPLY'] == '1', limit: limit)
    puts({ run_id: run.id, status: run.status, mode: run.mode, counts: run.summary }.to_json)
  end
end

namespace :places do
  desc 'Discover and resume nationwide facilities; APPLY=1 publishes verified entries only'
  task nationwide: :environment do
    batch_size = Integer(ENV.fetch('BATCH_SIZE', '10'), 10)
    runner = PlaceImports::NationwideRunner.new
    run = runner.call(apply: ENV['APPLY'] == '1', batch_size: batch_size, discover: ENV['DISCOVER'] != '0')
    puts({ run_id: run.id, status: run.status, mode: run.mode, counts: run.summary, progress: runner.report }.to_json)
  end

  desc 'Show persistent nationwide processing progress without making HTTP requests'
  task nationwide_status: :environment do
    puts PlaceImports::NationwideRunner.new.report.to_json
  end

  desc 'Retry explicitly reviewed pending candidate IDs with IDS=1,2,3'
  task nationwide_retry: :environment do
    raw = ENV.fetch('IDS')
    abort 'IDS must contain comma-separated numeric IDs' unless raw.match?(/\A[1-9][0-9]*(,[1-9][0-9]*)*\z/)
    puts({ requeued: PlaceImports::NationwideRunner.new.retry_pending(raw.split(',').map(&:to_i)) }.to_json)
  end
end
