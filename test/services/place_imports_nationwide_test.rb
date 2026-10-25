require 'test_helper'

class PlaceImportsNationwideTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  class Source
    attr_accessor :data, :directory_available, :failures
    attr_reader :requests
    def initialize(data)
      @data, @requests, @failures, @directory_available = data, [], [], false
    end
    def key; 'mizuno_nationwide'; end
    def seeds; data.map { |item| item.slice('name', 'url') }; end
    def discover
      raise PlaceImports::OfficialClient::FetchError, 'private response' unless directory_available
      seeds
    end
    def fetch(url)
      requests << url
      raise PlaceImports::OfficialClient::FetchError, 'private response' if failures.include?(url)
      data.find { |item| item['url'] == url }
    end
  end

  setup do
    category = Category.create!(name: '球技', kana: 'nationwide-ball', order: '1')
    @event = Event.create!(name: 'バスケ', ruby: 'nationwide-basketball', category: category, place: 1, order: '1')
    @prefecture = Prefecture.create!(name: '大阪府', kana: 'nationwide-osaka', order: '1')
    @city = City.create!(name: '吹田市', city_kana: 'suita', prefecture: @prefecture)
    @data = 3.times.map do |n|
      { 'name' => "全国体育館#{n}", 'url' => "https://shisetsu.mizuno.jp/m-test-#{n}", 'address' => "大阪府吹田市#{n + 1}-2-3",
        'prefecture' => '大阪府', 'city' => nil, 'tag' => '1', 'sports' => ['バスケットボール'],
        'access' => '駅徒歩5分', 'parking' => '20台', 'time' => '9:00～21:00', 'regular_holiday' => '月曜日',
        'scale' => 'バスケットボール1面', 'price' => '1時間1000円', 'alerts' => [],
        'evidence' => [{ 'text' => '公式の施設案内', 'url' => "https://shisetsu.mizuno.jp/m-test-#{n}/gallery" }] }
    end
    @source = Source.new(@data)
  end

  test 'maintenance does not stop known targets and a fresh runner resumes without republishing' do
    first = PlaceImports::NationwideRunner.new(source: @source).call(apply: true, batch_size: 1)
    assert_equal false, first.summary['directory_complete']
    assert_equal false, PlaceImports::NationwideRunner.new(source: @source).report[:complete]
    assert_equal 2, first.summary['remaining']
    assert_equal 1, Place.count
    assert_equal @city.id, Place.last.city_id
    assert_not_includes first.summary.to_json, 'private response'
    assert_difference('Place.count', 2) do
      second = PlaceImports::NationwideRunner.new(source: @source).call(apply: true)
      assert_equal 0, second.summary['remaining']
    end
    assert_no_difference('Place.count') { PlaceImports::NationwideRunner.new(source: @source).call(apply: true) }
    assert_equal 3, @source.requests.size
    assert_equal false, PlaceImports::NationwideRunner.new(source: @source).report[:complete]
    @source.directory_available = true
    PlaceImports::NationwideRunner.new(source: @source).call(apply: true)
    assert_equal true, PlaceImports::NationwideRunner.new(source: @source).report[:complete]
  end

  test 'preview advances past ready candidates and apply uses already collected facts' do
    assert_no_difference('Place.count') do
      runner = PlaceImports::NationwideRunner.new(source: @source)
      assert_equal 2, runner.call(batch_size: 1).summary['remaining']
      assert_equal 0, runner.call(batch_size: 20).summary['remaining']
    end
    assert_equal({ 'ready' => 3 }, PlaceImports::NationwideRunner.new(source: @source).progress)
    assert_difference('Place.count', 3) { PlaceImports::NationwideRunner.new(source: @source).call(apply: true) }
    assert_equal 3, @source.requests.size
  end

  test 'network errors insufficient facts and duplicates remain reviewable without blocking following candidates' do
    @source.failures << @data[0]['url']
    @data[1]['price'] = nil
    Place.create!(name: '既存体育館', prefecture: @prefecture, city: @city, events: [@event], tag: '1', address: @data[2]['address'])
    assert_no_difference('Place.count') do
      run = PlaceImports::NationwideRunner.new(source: @source).call(apply: true)
      assert_equal 0, run.summary['remaining']
    end
    assert_equal({ 'duplicate' => 1, 'pending' => 2 }, PlaceImports::NationwideRunner.new(source: @source).progress)
    assert_no_difference('Place.count') { PlaceImports::NationwideRunner.new(source: @source).call(apply: true) }
  end

  test 'an unexpected crash retains collected state and can be resumed without duplicate publication' do
    registrar = Object.new
    registrar.define_singleton_method(:call) { |*_, **_| raise 'unexpected_failure' }
    assert_raises(RuntimeError) { PlaceImports::NationwideRunner.new(source: @source, registrar: registrar).call(apply: true) }
    assert_equal 'failed', PlaceImportRun.last.status
    assert_equal 1, PlaceImportCandidate.where(status: 'collected').count
    assert_difference('Place.count', 3) { PlaceImports::NationwideRunner.new(source: @source).call(apply: true) }
    assert_equal 3, @source.requests.size
  end

  test 'a human dismissal during collection is never reset or published' do
    fetch = @source.method(:fetch)
    first_url = @data.first['url']
    @source.define_singleton_method(:fetch) do |url|
      data = fetch.call(url)
      PlaceImportCandidate.find_by!(source_url: url).update!(status: 'dismissed') if url == first_url
      data
    end
    assert_difference('Place.count', 2) { PlaceImports::NationwideRunner.new(source: @source).call(apply: true) }
    assert_equal 'dismissed', PlaceImportCandidate.find_by!(source_url: first_url).status
  end

  test 'explicit retry affects only specified pending entries and cannot reset registered entries' do
    @source.failures << @data[0]['url']
    runner = PlaceImports::NationwideRunner.new(source: @source)
    runner.call(apply: true)
    pending = PlaceImportCandidate.find_by!(status: 'pending')
    registered = PlaceImportCandidate.find_by!(status: 'registered')
    assert_equal 1, runner.retry_pending([pending.id, registered.id])
    assert_equal 'registered', registered.reload.status
    @source.failures.clear
    assert_difference('Place.count', 1) { runner.call(apply: true, discover: false) }
    assert_raises(ArgumentError) { runner.retry_pending([]) }
  end

  test 'a failed fetch cannot overwrite a simultaneous human dismissal' do
    @source.define_singleton_method(:fetch) do |url|
      PlaceImportCandidate.find_by!(source_url: url).update!(status: 'dismissed')
      raise PlaceImports::OfficialClient::FetchError, 'unavailable'
    end
    assert_no_difference('Place.count') { PlaceImports::NationwideRunner.new(source: @source).call(apply: true) }
    assert_equal({ 'dismissed' => 3 }, PlaceImports::NationwideRunner.new(source: @source).progress)
  end
end
