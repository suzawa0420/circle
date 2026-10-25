require 'digest'

module PlaceImports
  class Runner
    def initialize(source: SetagayaSource.new, registrar: Registrar.new)
      @source, @registrar = source, registrar
    end

    def call(apply: false, limit: 5)
      raise ArgumentError, 'limit must be 1..20' unless limit.is_a?(Integer) && (1..20).cover?(limit)
      # Single-server timer plus an OS lock prevents overlapping network scans.
      File.open(Rails.root.join('tmp', 'place-import.lock'), File::RDWR | File::CREAT, 0o600) do |lock|
        raise 'place_import_already_running' unless lock.flock(File::LOCK_EX | File::LOCK_NB)
        run = PlaceImportRun.create!(source: @source.key, mode: apply ? 'apply' : 'preview')
        counts = Hash.new(0)
        applied = 0
        begin
          @source.collect.each do |data|
            candidate = PlaceImportCandidate.find_or_initialize_by(source: @source.key, fingerprint: Digest::SHA256.hexdigest(data.fetch('url')))
            candidate.with_lock do
              candidate.assign_attributes(payload: data, source_url: data.fetch('url'), checked_at: Time.current, place_import_run: run)
              candidate.save!
            end
            # The cap limits actual insertions, not duplicates or review candidates.
            if candidate.status.in?(%w[registered dismissed])
              counts["already_#{candidate.status}"] += 1
              next
            end
            result = @registrar.call(candidate, apply: apply && applied < limit)
            applied += 1 if result == 'registered'
            counts[result] += 1
          end
          run.update!(status: 'completed', summary: counts)
        rescue StandardError => error
          # Never persist response bodies, exception messages, or request credentials.
          run.update!(status: 'failed', summary: counts.merge('error' => error.class.name))
          raise
        end
        run
      end
    end
  end
end
