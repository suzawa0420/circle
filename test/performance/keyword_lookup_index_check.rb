# No production Rails boot: connection is guarded by the disposable DB helper.
require_relative 'search_queries_check'
require_relative '../../db/migrate/20260925130000_add_db_keyword_lookup_index'
require 'json'
require 'digest'

ActiveRecord::Schema.define do
  create_table(:db_keywords, force: true) { |t| t.string :keyword }
end
class DbKeyword < ActiveRecord::Base; end

class KeywordLookupIndexTest < Minitest::Test
  def setup
    DbKeyword.delete_all
    @migration = AddDbKeywordLookupIndex.new
  end

  def teardown
    @migration.down
  end

  def test_exact_matches_duplicates_nulls_and_long_values_are_unchanged
    long_word = 200.times.map { |n| Digest::SHA256.hexdigest(n.to_s) }.join
    words = ['東京', '東京', 'Tokyo', 'tokyo', '東京 % _', '', nil, long_word]
    words.each { |word| DbKeyword.create!(keyword: word) }
    expected = words.map { |word| DbKeyword.where(keyword: word).order(:id).pluck(:id) }
    c = ActiveRecord::Base.connection
    before = %w[lock_timeout statement_timeout].map { |s| c.select_value("SHOW #{s}") }
    @migration.up
    @migration.up
    words.each_with_index do |word, i|
      assert_equal expected[i], DbKeyword.where(keyword: word).order(:id).pluck(:id)
    end
    refute DbKeyword.exists?(keyword: '存在しない')
    assert DbKeyword.create!(keyword: long_word + 'x').persisted?
    index = c.indexes(:db_keywords).find { |i| i.name == AddDbKeywordLookupIndex::INDEX_NAME }
    assert_equal :hash, index.using
    refute index.unique
    assert_equal true, c.select_value("SELECT indisvalid FROM pg_index WHERE indexrelid = #{c.quote(index.name)}::regclass")
    assert_equal before, %w[lock_timeout statement_timeout].map { |s| c.select_value("SHOW #{s}") }
    @migration.down
    refute c.index_name_exists?(:db_keywords, AddDbKeywordLookupIndex::INDEX_NAME)
  end

  def test_large_synthetic_lookup_uses_index
    c = ActiveRecord::Base.connection
    c.execute("INSERT INTO db_keywords (keyword) SELECT 'synthetic-' || n FROM generate_series(1, 240000) n")
    c.execute('ANALYZE db_keywords')
    sql = DbKeyword.where(keyword: 'synthetic-239999').limit(1).to_sql
    explain = lambda do
      raw = c.select_value('EXPLAIN (ANALYZE, FORMAT JSON) ' + sql)
      (raw.is_a?(String) ? JSON.parse(raw) : raw).first
    end
    before = explain.call
    @migration.up
    after = explain.call
    assert_includes after.to_json, AddDbKeywordLookupIndex::INDEX_NAME
    puts "Synthetic keyword lookup: before_ms=#{before['Execution Time']} after_ms=#{after['Execution Time']}"
  end

  def test_unexpected_existing_index_is_not_removed
    c = ActiveRecord::Base.connection
    name = AddDbKeywordLookupIndex::INDEX_NAME
    c.add_index :db_keywords, :keyword, name: name
    assert_raises(RuntimeError) { @migration.up }
    assert_equal :btree, c.indexes(:db_keywords).find { |i| i.name == name }.using
  end
end
