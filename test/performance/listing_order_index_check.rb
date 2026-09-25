# Standalone disposable PostgreSQL integration test; never boots production Rails.
require_relative 'search_queries_check'
require_relative '../../db/migrate/20260925103000_add_circle_listing_order_index'

class SearchQueriesTest
  def test_index_preserves_search_results_for_all_sorts_and_pages
    migration = AddCircleListingOrderIndex.new
    migration.up
    test_search_matches_legacy_for_all_sorts_pages_multiword_and_wildcards
  ensure
    migration.down if migration
  end
end

class ListingOrderIndexTest < Minitest::Test
  def test_concurrent_index_up_retry_and_down_restore_timeouts
    c = ActiveRecord::Base.connection
    migration = AddCircleListingOrderIndex.new
    name = AddCircleListingOrderIndex::INDEX_NAME
    before = %w[lock_timeout statement_timeout].map { |setting| c.select_value("SHOW #{setting}") }
    migration.up
    index = c.indexes(:users).find { |i| i.name == name }
    assert_equal %w[switch last_post], index.columns
    assert_equal({ 'last_post' => :desc }, index.orders)
    assert_equal true, c.select_value("SELECT indisvalid FROM pg_index WHERE indexrelid = #{c.quote(name)}::regclass")
    migration.up
    assert_equal 1, c.indexes(:users).count { |i| i.name == name }
    assert_equal before, %w[lock_timeout statement_timeout].map { |setting| c.select_value("SHOW #{setting}") }
    migration.down
    refute c.indexes(:users).any? { |i| i.name == name }
    assert_equal before, %w[lock_timeout statement_timeout].map { |setting| c.select_value("SHOW #{setting}") }
  ensure
    migration.down if migration
  end
end
