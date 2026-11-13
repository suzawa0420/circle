require 'digest'

module PlaceImports
  # Discovery is intentionally separate from publication. Unknown HTML must not
  # become a public facility merely because it came from an official domain.
  class OfficialDiscoveryRunner
    KEY = 'official_directory_discovery'.freeze
    REGISTRY = Rails.root.join('config/place_import_official_directories.json')

    def initialize(crawler_factory: nil)
      @crawler_factory = crawler_factory || lambda do |config|
        OfficialDiscoveryCrawler.new(config: config, client: DiscoveryClient.new(root: config.fetch('root')))
      end
    end

    def call
      File.open(Rails.root.join('tmp', 'place-official-discovery.lock'), File::RDWR | File::CREAT, 0o600) do |lock|
        return { status: 'already_running' } unless lock.flock(File::LOCK_EX | File::LOCK_NB)
        configs = JSON.parse(File.read(REGISTRY))
        configs.each do |config|
          source = PlaceDiscoverySource.find_by(prefecture_name: config.fetch('prefecture')) ||
            PlaceDiscoverySource.create_or_find_by!(prefecture_name: config.fetch('prefecture')) do |item|
              item.root_url = config.fetch('root')
              item.state = {}
            end
          source.with_lock do
            if source.root_url != config.fetch('root')
              # Registry changes cannot reuse another host's frontier.
              source.update!(root_url: config.fetch('root'), state: {}, last_checked_at: nil)
            end
          end
        end
        names = configs.map { |item| item.fetch('prefecture') }
        counts = Place.joins(:prefecture).group('prefectures.name').count
        source = PlaceDiscoverySource.where(prefecture_name: names).min_by do |item|
          [item.last_checked_at || Time.at(0), counts.fetch(item.prefecture_name, 0), item.id]
        end
        source.with_lock do
          # Recheck after obtaining the database lock so another host does not
          # immediately repeat a just-completed discovery batch.
          return { status: 'recently_checked' } if source.last_checked_at && source.last_checked_at > 5.minutes.ago
          config = configs.find { |item| item.fetch('prefecture') == source.prefecture_name }
          run = PlaceImportRun.create!(source: KEY, mode: 'discovery')
          begin
            previous_state = source.state || {}
            completed_at = previous_state['cycle_completed_at']
            rescan = completed_at.is_a?(Integer) && completed_at < 7.days.ago.to_i
            result = @crawler_factory.call(config).call(state: previous_state, rescan: rescan)
            added = 0
            result.fetch(:candidates).each do |item|
              url = item.fetch('url')
              fingerprint = Digest::SHA256.hexdigest(url)
              next if PlaceImportCandidate.exists?(source: KEY, fingerprint: fingerprint)
              # Existing adapter candidates remain their owner's responsibility.
              next if PlaceImportCandidate.where(source_url: url).exists?
              next if Place.where(url: url).exists?
              PlaceImportCandidate.create!(source: KEY, source_url: url, fingerprint: fingerprint,
                status: 'pending', payload: item, checked_at: Time.current, place_import_run: run,
                reason: '公式サイトから新規発見。施設実体・住所・種目・料金・営業時間・駐車場・休館情報を確認してから登録してください')
              added += 1
            end
            previous_errors = rescan ? [] : Array(previous_state['cycle_errors'])
            errors = (previous_errors + result.fetch(:errors)).uniq.select { |code| OfficialDiscoveryCrawler::ERROR_CODES.include?(code) }
            summary = result.fetch(:counters).stringify_keys.merge('prefecture' => source.prefecture_name, 'discovered' => added, 'errors' => errors)
            next_state = result.fetch(:state)
            next_state['cycle_errors'] = errors
            if next_state['complete']
              next_state['cycle_completed_at'] = (!rescan && completed_at) || Time.current.to_i
            end
            last_status = errors.empty? ? 'completed' : errors.first
            source.update!(state: next_state, last_checked_at: Time.current, last_status: last_status)
            run.update!(status: 'completed', summary: summary)
            { status: 'completed', run_id: run.id, counts: summary }
          rescue StandardError => error
            code = NationwideRunner::SAFE_ERROR_CODES.include?(error.message) ? error.message : 'source_error'
            source.update!(last_checked_at: Time.current, last_status: code)
            run.update!(status: 'failed', summary: { 'error_code' => code, 'prefecture' => source.prefecture_name })
            { status: 'failed', error_code: code }
          end
        end
      end
    end

    def report
      { scope: '47_prefectural_official_websites_not_all_municipalities',
        checked_sources: PlaceDiscoverySource.where.not(last_checked_at: nil).count,
        configured_sources: JSON.parse(File.read(REGISTRY)).size,
        pending_candidates: PlaceImportCandidate.where(source: KEY, status: 'pending').count,
        sources: PlaceDiscoverySource.order(:id).pluck(:prefecture_name, :last_checked_at, :last_status) }
    end
  end
end
