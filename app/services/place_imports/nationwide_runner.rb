require 'digest'

module PlaceImports
  class NationwideRunner
    PROCESSABLE = %w[queued collected ready].freeze
    RETRYABLE_ERRORS = [OfficialClient::FetchError, MizunoSource::SourceError, SetagayaSource::SourceError].freeze

    def initialize(source: MizunoSource.new, registrar: Registrar.new)
      @source, @registrar = source, registrar
    end

    def call(apply: false, batch_size: 10, discover: true)
      raise ArgumentError, 'batch_size must be 1..20' unless batch_size.is_a?(Integer) && (1..20).cover?(batch_size)
      File.open(Rails.root.join('tmp', 'place-import.lock'), File::RDWR | File::CREAT, 0o600) do |lock|
        raise 'place_import_already_running' unless lock.flock(File::LOCK_EX | File::LOCK_NB)
        run = PlaceImportRun.create!(source: @source.key, mode: apply ? 'apply' : 'preview')
        counts = Hash.new(0)
        begin
          if discover
            targets = @source.seeds
            begin
              targets += @source.discover
              counts['directory_complete'] = true
            rescue *RETRYABLE_ERRORS => error
              counts['directory_complete'] = false
              counts['directory_error'] = error.class.name
            end
            targets.uniq { |item| item.fetch('url') }.each do |seed|
              candidate = PlaceImportCandidate.find_or_initialize_by(source: @source.key,
                fingerprint: Digest::SHA256.hexdigest(seed.fetch('url')))
              next if candidate.persisted?
              candidate.assign_attributes(source_url: seed.fetch('url'), payload: seed,
                status: 'queued', reason: '公式施設ページの収集待ち', checked_at: Time.current, place_import_run: run)
              candidate.save!
              counts['discovered'] += 1
            end
          end
          states = apply ? PROCESSABLE : %w[queued collected]
          queue.where(status: states).order(:id).limit(batch_size).each do |candidate|
            begin
              if candidate.status == 'queued'
                data = @source.fetch(candidate.source_url)
                candidate.with_lock do
                  if candidate.status == 'queued'
                    candidate.update!(payload: data, status: 'collected', reason: '公式情報を収集済み・登録判定待ち',
                      checked_at: Time.current, place_import_run: run)
                  end
                end
              end
              # Publication and terminal queue status commit together. If killed,
              # the entire transaction rolls back and this item is resumable.
              candidate.with_lock do
                next unless PROCESSABLE.include?(candidate.status)
                candidate.update!(place_import_run: run)
                outcome = @registrar.call(candidate, apply: apply)
                candidate.update!(status: 'ready') if outcome == 'ready'
                counts[outcome] += 1
              end
            rescue *RETRYABLE_ERRORS => error
              candidate.with_lock do
                next unless PROCESSABLE.include?(candidate.status)
                candidate.update!(status: 'pending', reason: "公式情報の取得・形式を確認してください（#{error.class.name}）",
                  checked_at: Time.current, place_import_run: run)
                counts['pending'] += 1
              end
            end
          end
          counts['remaining'] = queue.where(status: apply ? PROCESSABLE : %w[queued collected]).count
          run.update!(status: 'completed', summary: counts)
        rescue StandardError => error
          run.update!(status: 'failed', summary: counts.merge('error' => error.class.name))
          raise
        end
        run
      end
    end

    def progress
      queue.group(:status).count
    end

    def report
      last_discovery = PlaceImportRun.where(source: @source.key).where('summary LIKE ?', '%"directory_complete":%').order(id: :desc).first
      discovered_all = last_discovery&.summary&.fetch('directory_complete', false) == true
      counts = progress
      { counts: counts, known_targets: counts.values.sum, remaining: counts.slice(*PROCESSABLE).values.sum,
        directory_complete: discovered_all, complete: discovered_all && counts.slice(*PROCESSABLE).values.sum.zero? }
    end

    def retry_pending(ids)
      raise ArgumentError, 'explicit numeric candidate IDs required' unless ids.any? && ids.all? { |id| id.is_a?(Integer) && id.positive? }
      queue.where(id: ids, status: 'pending').update_all(status: 'queued', reason: '管理者の指定により再収集待ち', updated_at: Time.current)
    end

    private

    def queue
      PlaceImportCandidate.where(source: @source.key)
    end
  end
end
