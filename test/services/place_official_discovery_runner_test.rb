require 'test_helper'

class PlaceOfficialDiscoveryRunnerTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  setup do
    @factories = []
    @results = []
    factory = lambda do |config|
      @factories << config
      results = @results
      crawler = Object.new
      crawler.define_singleton_method(:call) do |**_args|
        results.shift || { state: { 'complete' => true }, candidates: [], counters: { fetched: 1 }, errors: [] }
      end
      crawler
    end
    @runner = PlaceImports::OfficialDiscoveryRunner.new(crawler_factory: factory)
  end

  test 'rotates prefectures without publishing and persists duplicate-safe discovery' do
    config = JSON.parse(File.read(PlaceImports::OfficialDiscoveryRunner::REGISTRY)).first
    url = config.fetch('root') + 'sports/gym.html'
    result = { state: { 'complete' => true }, candidates: [{ 'url' => url, 'name' => '体育館', 'prefecture' => config.fetch('prefecture') }], counters: { fetched: 1 }, errors: [] }
    @results << result
    assert_no_difference('Place.count') { @runner.call }
    assert_equal 47, PlaceDiscoverySource.count
    candidate = PlaceImportCandidate.find_by(source_url: url)
    assert_equal 'pending', candidate.status
    assert_equal 1, @runner.report[:pending_candidates]
    assert candidate.reason.include?('確認')
    @results << result
    assert_no_difference('PlaceImportCandidate.count') { @runner.call }
    assert_equal 2, @factories.map { |item| item['prefecture'] }.uniq.size
  end

  test 'records crawl restrictions instead of claiming successful discovery' do
    @results << { state: {}, candidates: [], counters: { fetched: 0 }, errors: ['robots_unavailable'] }
    @runner.call
    assert_equal 'robots_unavailable', PlaceDiscoverySource.where.not(last_checked_at: nil).first.last_status
    assert_equal ['robots_unavailable'], PlaceImportRun.last.summary['errors']
  end

  test 'unknown crawler exceptions are safe and do not stop publication runner' do
    factory = ->(_config) { raise 'private response data' }
    result = PlaceImports::OfficialDiscoveryRunner.new(crawler_factory: factory).call
    assert_equal 'failed', result[:status]
    assert_equal 'source_error', result[:error_code]
    refute_includes PlaceImportRun.last.summary.to_json, 'private response'
  end
  test 'completed cycle retains restriction diagnostics until a fresh cycle' do
    @results << { state: { 'complete' => true }, candidates: [], counters: { fetched: 0 }, errors: ['robots_disallowed'] }
    @runner.call
    source = PlaceDiscoverySource.where.not(last_checked_at: nil).first
    PlaceDiscoverySource.update_all(last_checked_at: Time.current)
    source.update!(last_checked_at: 1.day.ago)
    @runner.call
    assert_equal 'robots_disallowed', source.reload.last_status
    assert_equal ['robots_disallowed'], source.state['cycle_errors']
  end

end
