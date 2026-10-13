# Synthetic-only database and publication/search fixtures from the guarded suite.
require_relative 'search_queries_check'
require_relative '../../db/migrate/20261010000000_add_public_visibility_index'
require_relative '../../db/migrate/20261013020000_add_public_circle_sort_indexes'

# Match the real columns rather than the older shared fixture's string appeal
# and timestamp last_post; predicate deparsing and ordered scans depend on types.
ActiveRecord::Schema.define do
  change_column :users, :appeal, :text
  change_column :users, :last_post, :string
end
User.reset_column_information

class SearchQueriesTest
  def test_public_sort_indexes_preserve_search_and_live_owner_moderation
    c = ActiveRecord::Base.connection
    migration = AddPublicCircleSortIndexes.new
    migration.verbose = false
    previous = %w[lock_timeout statement_timeout].map { |setting| c.select_value("SHOW #{setting}") }
    migration.up
    assert_equal AddPublicVisibilityIndex::PREDICATE, AddPublicCircleSortIndexes::PREDICATE
    assert_equal previous, %w[lock_timeout statement_timeout].map { |setting| c.select_value("SHOW #{setting}") }
    AddPublicCircleSortIndexes::INDEXES.each do |name, column|
      index = c.indexes(:users).find { |entry| entry.name == name }
      assert_equal ['switch', column.to_s], index.columns
      assert_equal({ column.to_s => :desc }, index.orders)
      assert_equal true, c.select_value("SELECT indisvalid FROM pg_index WHERE indexrelid=#{c.quote(name)}::regclass")
    end
    test_search_matches_legacy_for_all_sorts_pages_multiword_and_wildcards
    assert_raises(RuntimeError) { migration.up }
    assert_equal previous, %w[lock_timeout statement_timeout].map { |setting| c.select_value("SHOW #{setting}") }
    @admin.update!(check: AdminUser::SHADOW_BANNED_CHECK)
    %w[1 3].each do |sort|
      assert_empty search_page('東京', 1, sort).to_a
    end
  ensure
    migration.down if migration && c.index_name_exists?(:users, AddPublicCircleSortIndexes::INDEXES.keys.first)
  end

  def test_partial_ordered_scan_avoids_rechecking_profile_html
    c = ActiveRecord::Base.connection
    visibility = AddPublicVisibilityIndex.new
    migration = AddPublicCircleSortIndexes.new
    visibility.verbose = migration.verbose = false
    c.execute(<<~SQL)
      INSERT INTO users (admin_user_id, publication_status, moderation_status, ng_account,
        name, appeal, switch, last_post, created_at, prefecture_id, event_id, cb_point)
      SELECT #{@admin.id}, 'published', 'clear', NULL, 'English profile',
        repeat('<p>synthetic description</p>', 50) || CASE WHEN n % 5 = 0 THEN 'サークル紹介' ELSE '' END,
        '募集中', TIMESTAMP '2026-01-01' + n * INTERVAL '1 second',
        TIMESTAMP '2026-01-01' + n * INTERVAL '1 second', #{@pref.id}, #{@event.id}, 0
      FROM generate_series(1, 15000) n
    SQL
    c.add_index :users, [:switch, :last_post], order: { last_post: :desc }, name: 'synthetic_standard_order'
    c.add_index :users, [:switch, :created_at], order: { created_at: :desc }, name: 'synthetic_newest_order'
    visibility.up
    c.execute('ANALYZE users')
    c.execute('ANALYZE admin_users')
    before = {}
    expected = {}
    %w[1 3].each do |sort|
      relation = search_page('東京', 1, sort).except(:includes, :preload).offset(2000)
      expected[sort] = relation.pluck(:id)
      before[sort] = explain_public_sort(relation.to_sql)
    end
    migration.up
    c.execute('ANALYZE users')
    %w[1 3].each do |sort|
      relation = search_page('東京', 1, sort).except(:includes, :preload).offset(2000)
      assert_equal expected[sort], relation.pluck(:id)
      after = explain_public_sort(relation.to_sql)
      indexes = public_sort_nodes(after['Plan']).filter_map { |node| node['Index Name'] }
      expected_index = AddPublicCircleSortIndexes::INDEXES.keys[sort == '1' ? 0 : 1]
      assert_includes indexes, expected_index
      scan = public_sort_nodes(after['Plan']).find { |node| node['Index Name'] == expected_index }
      refute_includes scan.fetch('Filter', '').downcase, 'regexp_replace'
      c.execute('SET plan_cache_mode=force_generic_plan')
      c.execute("PREPARE public_sort_probe(integer, integer) AS #{relation.except(:limit, :offset).to_sql} LIMIT $1 OFFSET $2")
      generic = explain_public_sort('EXECUTE public_sort_probe(20, 2000)')
      assert_includes public_sort_nodes(generic['Plan']).filter_map { |node| node['Index Name'] }, expected_index
      c.execute('DEALLOCATE public_sort_probe')
      c.execute('RESET plan_cache_mode')
      puts "Synthetic sort=#{sort}: before=#{before[sort]['Execution Time']}ms after=#{after['Execution Time']}ms"
    end
  ensure
    c.execute('RESET plan_cache_mode') if c
    migration.down if migration && c.index_name_exists?(:users, AddPublicCircleSortIndexes::INDEXES.keys.first)
    visibility.down if visibility && c.index_name_exists?(:users, AddPublicVisibilityIndex::INDEX_NAME)
    %w[synthetic_standard_order synthetic_newest_order].each do |name|
      c.remove_index :users, name: name if c&.index_name_exists?(:users, name)
    end
  end

  def explain_public_sort(sql)
    JSON.parse(ActiveRecord::Base.connection.select_value("EXPLAIN (ANALYZE, FORMAT JSON) #{sql}")).first
  end

  def public_sort_nodes(node)
    [node] + Array(node['Plans']).flat_map { |child| public_sort_nodes(child) }
  end
end
