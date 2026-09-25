# Uses only the disposable database guarded by search_queries_check.rb.
require_relative 'search_queries_check'
require_relative '../../db/migrate/20260925120000_add_alternate_circle_listing_indexes'
require 'json'

class SearchQueriesTest
  def test_alternate_sorts_use_indexes_on_large_synthetic_search
    c = ActiveRecord::Base.connection
    # Synthetic text and IDs only. The temporary test database is guarded above.
    c.execute(<<~SQL)
      INSERT INTO users (name, appeal, switch, cb_point, last_post, created_at,
        schedule, area, recruitment, member, cost, goal, grouping, average_age)
      SELECT CASE WHEN n % 20 = 0 THEN '東京サークル' ELSE '大阪サークル' END,
        repeat('合成データの活動紹介', 20), '募集中', n % 1000,
        timestamp '2026-01-01' + n * interval '1 second',
        timestamp '2026-01-01' + n * interval '1 second',
        '週末', '大阪', repeat('仲間を募集中', 10), '社会人', '無料', '交流', '混合', '二十代'
      FROM generate_series(1, 76000) n
    SQL
    c.execute('ANALYZE users')
    queries = %w[2 3].map { |sort| search_page('東京', 1, sort).except(:includes, :preload).to_sql }
    explain = lambda do |sql|
      raw = c.select_value('EXPLAIN (ANALYZE, FORMAT JSON) ' + sql)
      (raw.is_a?(String) ? JSON.parse(raw) : raw).first
    end
    before = queries.map { |sql| explain.call(sql) }
    migration = AddAlternateCircleListingIndexes.new
    migration.up
    after = queries.map { |sql| explain.call(sql) }
    after.each_with_index do |plan, i|
      assert_includes plan.to_json, AddAlternateCircleListingIndexes::INDEXES.keys[i]
      puts "Synthetic sort=#{i + 2}: before_ms=#{before[i]['Execution Time']} after_ms=#{plan['Execution Time']}"
    end
  ensure
    migration.down if migration
  end

  def test_alternate_indexes_preserve_results_for_all_sorts_and_pages
    migration = AddAlternateCircleListingIndexes.new
    migration.up
    test_search_matches_legacy_for_all_sorts_pages_multiword_and_wildcards
  ensure
    migration.down if migration
  end
end

class AlternateListingIndexesTest < Minitest::Test
  def test_online_creation_retry_rollback_and_timeouts
    c = ActiveRecord::Base.connection
    migration = AddAlternateCircleListingIndexes.new
    before = %w[lock_timeout statement_timeout].map { |s| c.select_value("SHOW #{s}") }
    migration.up
    migration.up
    AddAlternateCircleListingIndexes::INDEXES.each do |name, definition|
      index = c.indexes(:users).find { |i| i.name == name }
      assert_equal definition[:columns], index.columns
      assert_equal definition[:orders], index.orders
      assert_equal true, c.select_value("SELECT indisvalid FROM pg_index WHERE indexrelid = #{c.quote(name)}::regclass")
      assert_equal 1, c.indexes(:users).count { |i| i.name == name }
    end
    assert_equal before, %w[lock_timeout statement_timeout].map { |s| c.select_value("SHOW #{s}") }
    migration.down
    assert_empty c.indexes(:users).map(&:name) & AddAlternateCircleListingIndexes::INDEXES.keys
  ensure
    migration.down if migration
  end

  def test_unexpected_existing_index_stops_without_removing_it
    c = ActiveRecord::Base.connection
    name = AddAlternateCircleListingIndexes::INDEXES.keys.first
    c.add_index :users, :switch, name: name
    before = %w[lock_timeout statement_timeout].map { |s| c.select_value("SHOW #{s}") }
    assert_raises(RuntimeError) { AddAlternateCircleListingIndexes.new.up }
    assert_equal ['switch'], c.indexes(:users).find { |i| i.name == name }.columns
    assert_equal before, %w[lock_timeout statement_timeout].map { |s| c.select_value("SHOW #{s}") }
  ensure
    c.remove_index :users, name: name if c && name && c.index_name_exists?(:users, name)
  end
end
