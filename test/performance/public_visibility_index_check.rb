# Standalone, destructive only within this specifically named synthetic DB.
# Run with the temporary cluster's Unix socket (port 55442). Never boots Rails.
require 'bundler/setup'
require 'minitest/autorun'
require 'active_record'
require 'active_support/all'
require 'json'

socket = ARGV.shift
abort 'Dedicated temporary socket required' unless socket&.match?(%r{\A/private/tmp/circle-performance-pg(?:\.[a-zA-Z0-9]+)?/socket\z})
ActiveRecord::Base.establish_connection(adapter: 'postgresql', host: socket,
  port: 55442, database: 'circle_visibility_index_test')
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table(:admin_users, force: true) { |t| t.integer :check }
  create_table(:users, force: true) do |t|
    t.bigint :admin_user_id
    t.string :publication_status
    t.string :moderation_status
    t.string :ng_account
    t.string :name
    t.text :appeal
  end
end

class AdminUser < ActiveRecord::Base
  source = File.read(File.expand_path('../../app/models/admin_user.rb', __dir__))
  class_eval(source[/^\s*SHADOW_BANNED_CHECK = .*$/])
  class_eval(source[/^\s*scope :publicly_visible, .*$/])
end
class User < ActiveRecord::Base
  source = File.read(File.expand_path('../../app/models/user.rb', __dir__))
  class_eval(source[/scope :publicly_visible, -> \{.*?\n\s*\}/m])
end
require_relative '../../db/migrate/20261010000000_add_public_visibility_index'

class PublicVisibilityIndexTest < Minitest::Test
  def test_same_policy_with_index_only_and_generic_prepared_plans
    c = ActiveRecord::Base.connection
    owner = AdminUser.create!(check: nil)
    blocked = AdminUser.create!(check: AdminUser::SHADOW_BANNED_CHECK)
    c.execute(<<~SQL)
      INSERT INTO users (admin_user_id, publication_status, moderation_status, ng_account, name, appeal)
      SELECT #{owner.id}, 'published', 'clear', NULL, 'English title',
        repeat('<p>synthetic description</p>', 50) || CASE WHEN n % 5 = 0 THEN 'サークル紹介' ELSE '' END
      FROM generate_series(1, 15000) n
    SQL
    # Include statuses, nulls, moderation decisions, and kana appearing only in
    # markup. The predicate must never expose an owner blocked after publication.
    [owner.id, blocked.id, nil].product(['published', 'draft'], ['clear', 'review'],
      [nil, 'OK', 'NG'], [nil, 'English', '<b title="カナ">English</b>', '日本語の会']).each do |owner_id, publication, moderation, ng, name|
      User.create!(admin_user_id: owner_id, publication_status: publication,
        moderation_status: moderation, ng_account: ng, name: name, appeal: nil)
    end
    old = User.where(publication_status: 'published', moderation_status: 'clear')
      .where(ng_account: [nil, 'OK']).where(admin_user_id: AdminUser.publicly_visible.select(:id))
      .where("REGEXP_REPLACE(COALESCE(users.name, ''), '<[^>]*>', '', 'g') ~ :kana OR REGEXP_REPLACE(COALESCE(users.appeal, ''), '<[^>]*>', '', 'g') ~ :kana", kana: '[ぁ-んァ-ヶ]')
    expected = old.order(:id).pluck(:id)
    assert_equal expected, User.publicly_visible.order(:id).pluck(:id)
    c.execute('VACUUM ANALYZE users')
    c.execute('ANALYZE admin_users')
    sql = User.publicly_visible.reselect('COUNT(*)').to_sql
    before = explain(sql)
    lock_timeout = c.select_value('SHOW lock_timeout')
    statement_timeout = c.select_value('SHOW statement_timeout')
    migration = AddPublicVisibilityIndex.new
    migration.verbose = false
    migration.up
    c.execute('ANALYZE users')
    assert_equal lock_timeout, c.select_value('SHOW lock_timeout')
    assert_equal statement_timeout, c.select_value('SHOW statement_timeout')
    assert_equal expected, User.publicly_visible.order(:id).pluck(:id)
    after = explain(sql)
    assert includes_index?(after['Plan']), 'Count must use the partial visibility index without evaluating profile HTML'
    c.execute('SET plan_cache_mode = force_generic_plan')
    c.execute("PREPARE visibility_probe(bigint) AS #{sql} AND users.id > $1")
    generic = explain('EXECUTE visibility_probe(0)')
    assert includes_index?(generic['Plan']), 'Fixed publication policy must remain indexable with generic prepared plans'
    c.execute('DEALLOCATE visibility_probe')
    c.execute('RESET plan_cache_mode')
    owner.update!(check: AdminUser::SHADOW_BANNED_CHECK)
    assert_empty User.publicly_visible, 'Owner moderation must take effect immediately, without a backfill or cache TTL'
    migration.down
    refute c.index_name_exists?(:users, AddPublicVisibilityIndex::INDEX_NAME)
    puts "Synthetic count: before=#{before['Execution Time']}ms after=#{after['Execution Time']}ms generic=#{generic['Execution Time']}ms; policy rows=#{expected.length}"
  end

  def explain(sql)
    JSON.parse(ActiveRecord::Base.connection.select_value("EXPLAIN (ANALYZE, FORMAT JSON) #{sql}")).first
  end

  def includes_index?(node)
    node['Index Name'] == AddPublicVisibilityIndex::INDEX_NAME || (node['Plans'] || []).any? { |child| includes_index?(child) }
  end
end
