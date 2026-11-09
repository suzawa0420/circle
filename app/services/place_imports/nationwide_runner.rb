require 'digest'

module PlaceImports
  class NationwideRunner
    PROCESSABLE = %w[queued collected ready].freeze
    RETRYABLE_ERRORS = [OfficialClient::FetchError, MizunoSource::SourceError, SetagayaSource::SourceError, SapporoSource::SourceError, SendaiSource::SourceError, KochiSource::SourceError, MiyazakiSource::SourceError].freeze
    # Persist only reviewed diagnostic codes, never remote bodies or exception text.
    SAFE_ERROR_CODES = %w[robots_disallowed http_error network_error response_too_large invalid_encoding
      unapproved_url directory_pagination_loop directory_page_limit empty_or_changed_directory
      unapproved_facility_url missing_facility_metadata directory_scope_unverified partial_reviewed_seed_only
      unverified_rate_qualifications unverified_booking_qualifications unverified_notice_structure
      unsupported_rate_table missing_facility_content changed_facility_identity changed_available_sports
      missing_access changed_current_rate_link changed_rate_qualifications unreviewed_rate_document
      invalid_content_type invalid_pdf unreviewed_source_change].freeze

    def initialize(source: nil, sources: nil, registrar: Registrar.new)
      raise ArgumentError, 'choose source or sources, not both' if source && sources
      @sources = sources || [source || MizunoSource.new]
      unless @sources.is_a?(Array) && @sources.any? && @sources.map(&:key).uniq.size == @sources.size
        raise ArgumentError, 'reviewed sources must be a nonempty list with unique keys'
      end
      @source, @registrar = @sources.first, registrar
    end

    def call(apply: false, batch_size: 10, discover: true)
      raise ArgumentError, 'batch_size must be 1..20' unless batch_size.is_a?(Integer) && (1..20).cover?(batch_size)
      File.open(Rails.root.join('tmp', 'place-import.lock'), File::RDWR | File::CREAT, 0o600) do |lock|
        raise 'place_import_already_running' unless lock.flock(File::LOCK_EX | File::LOCK_NB)
        mode = apply ? 'apply' : 'preview'
        # Pick inside the shared nonblocking lock. Attempts, including failed or
        # interrupted ones, rotate fairly; previews never consume an apply turn.
        latest = PlaceImportRun.where(source: @sources.map(&:key), mode: mode).group(:source).maximum(:id)
        @source = @sources.each_with_index.min_by { |source, index| [latest.fetch(source.key, 0), index] }.first
        run = PlaceImportRun.create!(source: @source.key, mode: mode)
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
              counts['directory_error_code'] = safe_error_code(error)
              if @source.respond_to?(:discover_related)
                previous = PlaceImportRun.where(source: @source.key)
                  .where('summary LIKE ?', '%"related_cursor":%').order(id: :desc).first
                related = @source.discover_related(urls: targets.map { |item| item.fetch('url') } + queue.pluck(:source_url),
                  after: previous&.summary&.fetch('related_cursor', nil), limit: 10)
                targets += related.fetch(:targets)
                counts['related_cursor'] = related.fetch(:cursor)
                counts['related_inspected'] = related.fetch(:inspected)
                counts['related_failed'] = related.fetch(:failed)
              end
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
              refresh_before_apply = apply && @source.respond_to?(:revalidate_before_apply?) && @source.revalidate_before_apply?
              if candidate.status == 'queued' || refresh_before_apply
                data = @source.fetch(candidate.source_url)
                candidate.with_lock do
                  if candidate.status == 'queued' || (refresh_before_apply && PROCESSABLE.include?(candidate.status))
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
      PlaceImportCandidate.where(source: @sources.map(&:key)).group(:status).count
    end

    def report
      reports = @sources.to_h { |source| [source.key, source_report(source)] }
      return reports.values.first if @sources.one?
      counts = progress
      {
        counts: counts, known_targets: counts.values.sum, remaining: counts.slice(*PROCESSABLE).values.sum,
        coverage_scope: 'reviewed_sources_only',
        directory_complete: reports.values.all? { |report| report[:directory_complete] },
        complete: reports.values.all? { |report| report[:complete] },
        source_review_required: reports.values.any? { |report| report[:source_review_required] },
        sources: reports
      }
    end

    def retry_pending(ids)
      raise ArgumentError, 'choose one explicit source before retrying' unless @sources.one?
      raise ArgumentError, 'explicit numeric candidate IDs required' unless ids.any? && ids.all? { |id| id.is_a?(Integer) && id.positive? }
      queue.where(id: ids, status: 'pending').update_all(status: 'queued', reason: '管理者の指定により再収集待ち', updated_at: Time.current)
    end

    private

    def source_report(source)
      last_discovery = PlaceImportRun.where(source: source.key).where('summary LIKE ?', '%"directory_complete":%').order(id: :desc).first
      last_apply = PlaceImportRun.where(source: source.key, mode: 'apply').order(id: :desc).first
      discovered_all = last_discovery&.summary&.fetch('directory_complete', false) == true
      candidates = PlaceImportCandidate.where(source: source.key)
      counts = candidates.group(:status).count
      stored_error = last_discovery&.summary&.fetch('directory_error_code', nil)
      { counts: counts, known_targets: counts.values.sum, remaining: counts.slice(*PROCESSABLE).values.sum,
        coverage_scope: 'reviewed_sources_only',
        directory_complete: discovered_all, complete: discovered_all && counts.slice(*PROCESSABLE).values.sum.zero?,
        directory_error_code: stored_error.nil? ? nil : safe_diagnostic_code(stored_error),
        source_review_required: !discovered_all && counts.slice(*PROCESSABLE).values.sum.zero?,
        related_inspected: safe_count(last_discovery&.summary&.fetch('related_inspected', 0)),
        related_failed: safe_count(last_discovery&.summary&.fetch('related_failed', 0)),
        # Read-only timestamps distinguish a healthy but exhausted source from
        # a stopped scheduler. Preview runs must not mask an absent apply run.
        last_apply_run_id: last_apply&.id,
        last_apply_at: last_apply&.created_at&.iso8601,
        last_apply_status: last_apply && (%w[running completed failed].include?(last_apply.status) ? last_apply.status : 'unknown'),
        last_discovered_at: candidates.maximum(:created_at)&.iso8601,
        last_published_at: candidates.where(status: 'registered').joins(:place).maximum('places.created_at')&.iso8601,
        oldest_unprocessed_at: candidates.where(status: PROCESSABLE).minimum(:created_at)&.iso8601 }
    end

    def safe_error_code(error)
      safe_diagnostic_code(error.message)
    end

    def safe_diagnostic_code(value)
      SAFE_ERROR_CODES.include?(value) ? value : 'source_error'
    end

    def safe_count(value)
      value.is_a?(Integer) && value >= 0 ? value : 0
    end

    def queue
      PlaceImportCandidate.where(source: @source.key)
    end
  end
end
