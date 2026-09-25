# Standalone: synthetic data only, using the guarded disposable DB connection.
# Run separately from match_queries_check.rb because both extend the test schema.
require_relative 'circle_listing_data_check'
require 'action_controller'
require 'active_support/testing/time_helpers'
require_relative '../../app/services/search_result_count_cache'
# Existing Rails 6.0 scope deprecations are unrelated to this regression check.
ActiveSupport::Deprecation.silenced = true

ActiveRecord::Schema.define do
  add_column :events, :ruby, :string
  add_column :prefectures, :kana, :string
  add_column :prefectures, :order, :integer
  add_column :tags, :name, :string
  %i[name schedule area recruitment member cost goal grouping average_age appeal ng_account template].each do |column|
    add_column :users, column, :string
  end
  %i[last_post created_at].each { |column| add_column :users, column, :datetime }
  add_column :users, :cb_point, :integer
  add_column :users, :admin_user_id, :bigint
  create_table(:cities, force: true) { |t| t.string :name; t.string :city_kana; t.bigint :prefecture_id }
  create_table(:users_cities, force: true) { |t| t.bigint :user_id; t.bigint :city_id }
  create_table(:categories, force: true)
  create_table(:ages, force: true)
  create_table(:groups, force: true)
  create_table(:admin_users, force: true) { |t| t.string :check }
  create_table(:user_contacts, force: true) do |t|
    t.bigint :user_id; t.string :ip_address; t.string :account_block; t.string :entry; t.string :message
  end
end

class City < ActiveRecord::Base
  has_many :users_cities
end
class UsersCity < ActiveRecord::Base
  belongs_to :user, optional: true
end
class Category < ActiveRecord::Base; end
class Age < ActiveRecord::Base; end
class Group < ActiveRecord::Base; end
class AdminUser < ActiveRecord::Base; end
class UserContact < ActiveRecord::Base; end
class UserTag
  belongs_to :user
end
class Tag
  has_many :user_tags
end
class User
  has_many :user_contacts
  # Use the real scope definitions without booting Rails/reading credentials.
  source = File.read(File.expand_path('../../app/models/user.rb', __dir__))
  scope_names = %w[list sort_1 sort_2 sort_3 ng_account user_sort_1 user_sort_2 user_sort_3 prefecture prefecture_sub prefecture_50 city tag event]
  source.each_line do |line|
    class_eval(line) if line.match?(/^\s*scope :(#{scope_names.join('|')}),/)
  end
  class_eval(source[/scope :search_word, ->\(keyword\) do.*?\n\s*end/m])
end
module ApplicationHelper; end
module Circlebook; end
class ApplicationController < ActionController::Base
  def admin_user_signed_in?; false; end
end
module Circles; end
require_relative '../../app/controllers/circles/application_controller'
require_relative '../../app/controllers/circles/search_controller'
require_relative '../../app/controllers/tags_controller'
require_relative '../../app/controllers/user_contacts_controller'

class SearchQueriesTest < Minitest::Test
  include ActiveSupport::Testing::TimeHelpers
  def setup
    SearchResultCountCache::STORE.clear
    [UserContact, AdminUser, UsersCity, UserTag, Review, Schedule, User, Tag, City, Event, Prefecture].each(&:delete_all)
    @event = Event.create!(name: 'バスケ', ruby: 'basketball')
    @pref = Prefecture.create!(name: '東京', kana: 'tokyo')
    @city = City.create!(name: '渋谷', city_kana: 'shibuya', prefecture_id: @pref.id)
    @tag = Tag.create!(name: '初心者')
    @admin = AdminUser.create!(check: nil)
    @users = 45.times.map do |i|
      User.create!(name: "circle #{i}", appeal: '楽しく活動', switch: '募集中',
        event: @event, prefecture: @pref, admin_user_id: @admin.id,
        last_post: Time.at(1000 + i), created_at: Time.at(2000 - i), cb_point: i)
    end
    @users.each do |u|
      UserTag.create!(user_id: u.id, tag_id: @tag.id)
      UsersCity.create!(user_id: u.id, city_id: @city.id)
    end
    # Duplicate memberships must not duplicate the displayed circles.
    UserTag.create!(user_id: @users.first.id, tag_id: @tag.id)
    UsersCity.create!(user_id: @users.first.id, city_id: @city.id)
    @nationwide = User.create!(name: '全国', appeal: '活動', switch: '募集中', prefecture_id: 50,
      event: @event, last_post: Time.at(1), created_at: Time.at(1), cb_point: -1)
    UserTag.create!(user_id: @nationwide.id, tag_id: @tag.id)
    User.create!(name: '対象外', appeal: '', switch: '募集中', event: @event, prefecture: @pref)
    User.create!(name: '非公開', appeal: '活動', switch: '募集中', ng_account: 'NG', event: @event, prefecture: @pref)
  end

  def capture
    sql = []
    records = Hash.new(0)
    q = ->(*args) { p = args.last; sql << p[:sql] if p[:sql].start_with?('SELECT') && p[:name] != 'SCHEMA' }
    r = ->(*args) { p = args.last; records[p[:class_name]] += p[:record_count] }
    ActiveSupport::Notifications.subscribed(q, 'sql.active_record') do
      ActiveSupport::Notifications.subscribed(r, 'instantiation.active_record') { yield }
    end
    [sql, records]
  end

  def test_tag_actions_keep_results_order_and_pages_without_loading_memberships
    [:event, :event_prefecture, :event_prefecture_city, :prefecture, :prefecture_city].each do |action|
      %w[1 2 3].each do |sort|
        [1, 2, 3].each do |page|
          controller = TagsController.new
          controller.params = ActionController::Parameters.new(id: @tag.id, ruby: 'basketball', kana: 'tokyo', city_kana: 'shibuya', sort: sort, page: page)
          sql, records = capture do
            controller.send(:set_tags)
            controller.public_send(action)
          end
          assert_equal 0, records['User']
          assert_equal 0, records['UserTag']
          assert_equal 0, records['UsersCity']
          assert_operator sql.length, :<=, 5
          relation = controller.instance_variable_get(:@users)
          expected = User.where(id: @users.map(&:id) + [@nationwide.id]).public_send("user_sort_#{sort}").page(page)
          assert_equal expected.pluck(:id), relation.pluck(:id)
          assert_equal expected.total_count, relation.total_count
        end
      end
    end
  end

  def test_tag_membership_query_count_is_constant
    old_ids = nil
    before, records = capture { old_ids = @tag.user_tags.map { |membership| membership.user.id } }
    after, new_records = capture do
      assert_equal old_ids.uniq.sort, User.where(id: @tag.user_tags.select(:user_id)).order(:id).pluck(:id)
    end
    assert_operator before.length, :>, 40
    assert_operator records['User'], :>, 40
    assert_equal 1, after.length
    assert_equal 0, new_records['User']
    puts "Tag membership: #{before.length} SELECTs before, #{after.length} after"
  end

  def legacy_search(query)
    users = User
    query.split(/[[:blank:]]+/).select(&:present?).each do |keyword|
      events = Event.where('name LIKE ?', "%#{keyword}%").pluck(:id)
      prefs = Prefecture.where('name LIKE ?', "%#{keyword}%").pluck(:id)
      cities = UsersCity.where(city_id: City.where('name LIKE ?', "%#{keyword}%").pluck(:id)).pluck(:user_id)
      tags = UserTag.where(tag_id: Tag.where('name LIKE ?', "%#{keyword}%").pluck(:id)).pluck(:user_id)
      users = legacy_text_search(users, keyword).or(users.where(event_id: events)).or(users.where(prefecture_id: prefs)).or(users.where(prefecture_sub_id: prefs)).or(users.where(id: cities)).or(users.where(id: tags))
    end
    users.list
  end

  # Freeze the old text predicates independently of the production scope.
  def legacy_text_search(users, keyword)
    text = users.where('LOWER(name) LIKE ?', "%#{keyword.downcase}%")
    %w[schedule area recruitment member cost goal grouping average_age].each do |field|
      text = text.or(users.where("#{field} LIKE ?", "%#{keyword}%"))
    end
    text.or(users.where('LOWER(appeal) LIKE ?', "%#{keyword.downcase}%"))
  end

  def test_search_matches_legacy_for_all_sorts_pages_multiword_and_wildcards
    ['バスケ', '東京 初心者', '渋谷 circle', '初心者　バスケ', '楽しく', 'CIRCLE', '%', "'", '存在しない', ''].each do |query|
      %w[1 2 3].each do |sort|
        [1, 2, 3].each do |page|
          controller = Circles::SearchController.new
          controller.params = ActionController::Parameters.new(q: query, sort: sort, page: page)
          sql, records = capture { controller.send(:set_keyword_search) }
          assert_empty sql, 'Building search must not fetch ID arrays'
          assert_empty records
          relation = controller.instance_variable_get(:@users)
          expected = legacy_search(query).public_send("sort_#{sort}").page(page)
          # pluck with includes forces JOINs that normal listing rendering avoids.
          assert_equal expected.except(:includes).pluck(:id), relation.except(:includes).pluck(:id), "#{query} sort=#{sort} page=#{page}"
          assert_equal expected.total_count, relation.total_count
          assert_equal(expected.count.positive?, relation.exists?)
          assert_equal expected.except(:includes).pluck(:id), CircleListingData.new(relation).users.map(&:id)
        end
      end
    end
    original, = capture { legacy_search('東京 初心者') }
    puts "Keyword preparation: #{original.length} SELECTs before, 0 after (2 keywords)"
  end

  def test_contacts_do_not_instantiate_all_admins_and_preserve_recommendations
    AdminUser.insert_all!(Array.new(100) { { check: nil } })
    controller = UserContactsController.new
    controller.params = ActionController::Parameters.new
    controller.request = ActionDispatch::TestRequest.create
    controller.instance_variable_set(:@user, @users.first)
    sql, records = capture { controller.new }
    assert_equal 0, records['AdminUser']
    assert_equal @users.drop(1).reverse.map(&:id), controller.instance_variable_get(:@users).pluck(:id)
    assert_equal '参加', controller.instance_variable_get(:@user_contact).entry
    assert_operator sql.length, :<=, 2
  end

  def test_search_preserves_each_text_and_association_branch
    fields = %i[name schedule area recruitment member cost goal grouping average_age appeal]
    fields.each do |field|
      User.create!({ name: nil, appeal: '活動', switch: '募集中' }.merge(field => 'NeedleAbC'))
    end
    # Match each association independently; other searchable fields stay NULL.
    event = Event.create!(name: 'RelationHit')
    pref = Prefecture.create!(name: 'RelationHit')
    city = City.create!(name: 'RelationHit')
    tag = Tag.create!(name: 'RelationHit')
    attrs = { appeal: '活動', switch: '募集中' }
    User.create!(attrs.merge(event_id: event.id))
    User.create!(attrs.merge(prefecture_id: pref.id))
    User.create!(attrs.merge(prefecture_sub_id: pref.id))
    city_user = User.create!(attrs)
    UsersCity.create!(user_id: city_user.id, city_id: city.id)
    tag_user = User.create!(attrs.merge(name: 'NeedleAbC'))
    2.times { UserTag.create!(user_id: tag_user.id, tag_id: tag.id) }
    [nil, '', 'NG'].each do |value|
      User.create!(attrs.merge(name: 'NeedleAbC', appeal: value, ng_account: 'NG'))
    end

    ['NeedleAbC', 'needleabc', 'RelationHit', 'RelationHit NeedleAbC',
     'NeedleAbC RelationHit', 'Needle%', 'Needle_bC', "'", '', '該当なし'].each do |word|
      SearchResultCountCache::STORE.clear
      actual = search_page(word).except(:includes, :preload, :order, :limit, :offset)
      expected = legacy_search(word).except(:includes, :order)
      assert_equal expected.order(:id).pluck(:id), actual.order(:id).pluck(:id), word
      assert_equal expected.count, actual.count, word
    end
  end

  def test_japanese_literals_skip_lower_but_preserve_unicode_and_like_semantics
    samples = ['東京ABC', 'abc東京', 'とうきょう', 'バスケ', 'サークル',
      'ＡＢＣ東京', 'İ東京Σ', '東京初心者', '初心者', 'École', 'Σίσυφος',
      '東京_ABC', '東京%ABC', "東京\\ABC", nil, '']
    samples.each { |text| User.create!(name: text, appeal: text, switch: '募集中') }
    ['東京', 'とうきょう', 'バスケ', 'サークル', '初心者', '漢字',
     'ABC', 'abc', 'ＡＢＣ', 'İ', 'Σ', 'É', '東京ABC', '東京_', '東京%',
     "東京\\", '', '東京 初心者'].each do |word|
      expected = legacy_text_search(User.all, word).order(:id).pluck(:id)
      assert_equal expected, User.search_word(word).order(:id).pluck(:id), word
      sql = User.search_word(word).to_sql
      if word.match?(/\A[ぁ-んァ-ヶ一-龥ー]+\z/)
        refute_includes sql, 'LOWER('
      else
        assert_includes sql, 'LOWER(name)'
        assert_includes sql, 'LOWER(appeal)'
      end
    end
  end

  def test_search_render_reuses_loaded_page_and_eliminates_redundant_count
    controller = Circles::SearchController.new
    controller.params = ActionController::Parameters.new(q: '東京', sort: '1', page: 1)
    controller.send(:set_keyword_search)
    relation = controller.instance_variable_get(:@users)
    relation = User.where(relation.where_clause.ast).order(switch: :asc, last_post: :desc).page(1)
    queries = nil
    ActiveRecord::Base.connection.unprepared_statement do
      queries, = capture do
        if relation.size != 0
          data = CircleListingData.new(relation)
          data.users.to_a
          data.users.total_pages
        end
      end
    end
    searches = queries.select { |sql| sql.include?('FROM "users_cities"') }
    assert_equal 3, searches.length
    searches.each do |sql|
      plan = JSON.parse(ActiveRecord::Base.connection.select_value("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) #{sql}")).first
      puts "Synthetic plan: #{plan['Plan']['Node Type']}, execution=#{plan['Execution Time']}ms"
    end
    controller.send(:set_keyword_search)
    data = controller.instance_variable_get(:@listing_data)
    relation = controller.instance_variable_get(:@users)
    assert_same data.users, relation
    after, records = capture do
      assert relation.load.any?
      assert_equal @users.reverse.first(20).map(&:id), data.users.map(&:id)
      assert_equal 3, data.users.total_pages
    end
    search_count = after.count { |sql| sql.include?('FROM "users_cities"') }
    assert_equal 2, search_count
    assert_equal 20, records['User']
    assert_equal 0, records['Review']
    puts "Search render: #{searches.length} search SQLs before, #{search_count} after"
  end

  def test_search_templates_compile_and_share_listing_data
    %w[index show].each do |action|
      source = File.read(File.expand_path("../../app/views/circles/search/#{action}.html.haml", __dir__))
      RubyVM::InstructionSequence.compile(Haml::Engine.new.call(source))
      assert_includes source, '@users.load.any?'
      assert_includes source, 'listing_data: @listing_data'
      refute_match(/@users.*\.size/, source)
    end
  end

  def test_last_and_empty_pages_use_loaded_results_without_extra_empty_state_queries
    [3, 4].each do |page|
      controller = Circles::SearchController.new
      controller.params = ActionController::Parameters.new(q: '東京', sort: '1', page: page)
      controller.send(:set_keyword_search)
      data = controller.instance_variable_get(:@listing_data)
      relation = controller.instance_variable_get(:@users)
      queries, = capture do
        present = relation.load.any?
        assert_equal(page == 3, present)
        assert_equal(page == 3 ? 5 : 0, relation.size)
        assert_same relation, data.users
        assert_equal 3, data.users.total_pages if present
      end
      assert_equal 1, queries.count { |sql| sql.include?('FROM "users_cities"') }
    end
  end

  def search_page(word = '東京', page = 1, sort = '1')
    controller = Circles::SearchController.new
    controller.params = ActionController::Parameters.new(q: word, sort: sort, page: page)
    controller.send(:set_keyword_search)
    controller.instance_variable_get(:@users)
  end

  def test_count_cache_reuses_only_counts_and_expires_after_thirty_seconds
    travel_to(Time.utc(2026, 9, 25, 12)) do
      first = search_page
      assert_equal 45, first.total_count
      @users.first.update!(ng_account: 'NG')
      current = search_page('東京', 1, '2')
      sql, = capture do
        refute_includes current.to_a.map(&:id), @users.first.id
        assert_equal 45, current.total_count
      end
      refute sql.any? { |q| q.include?('COUNT(*)') }
      assert_equal 45, search_page('東京', 2).total_count
      travel 31.seconds
      assert_equal 44, search_page.total_count
    end
  end

  def test_count_cache_keeps_search_conditions_separate
    assert_equal 45, search_page.total_count
    assert_equal 0, search_page('存在しないキーワード').total_count
    assert_equal 1, search_page('circle 44').total_count
    sql, = capture { assert_equal 45, search_page.total_count }
    assert_empty sql
    # A fresh plain relation (used by all other listings) is not opted in.
    refute User.list.is_a?(SearchResultCountCache::RelationMethods)
  end
end
