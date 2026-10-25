namespace :places do
  desc 'Collect official facility candidates; APPLY=1 registers up to LIMIT (default 5)'
  task discover: :environment do
    limit = Integer(ENV.fetch('LIMIT', '5'), 10)
    run = PlaceImports::Runner.new.call(apply: ENV['APPLY'] == '1', limit: limit)
    puts({ run_id: run.id, status: run.status, mode: run.mode, counts: run.summary }.to_json)
  end
end
