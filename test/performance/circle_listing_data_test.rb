# Standalone integration test against an isolated, disposable PostgreSQL cluster.
# Usage: bundle exec ruby test/performance/circle_listing_data_test.rb /private/tmp/circle-list-pg.XXXXXX
# Does not boot Rails, read credentials, or connect to the application database.
require 'bundler/setup'
require 'minitest/autorun'
require 'active_record'
require 'active_support/all'
require 'kaminari/activerecord'
require 'haml'

socket = ARGV.shift
abort 'Pass the dedicated temporary PostgreSQL socket directory' unless socket&.match?(%r{\A/private/tmp/circle-list-pg\.[a-zA-Z0-9]+\z})
ActiveRecord::Base.establish_connection(adapter: 'postgresql', host: socket,
  port: 55439, database: 'circle_listing_test')
ActiveRecord::Schema.define do
  create_table(:prefectures, force: true) { |t| t.integer :sort; t.string :name }
  create_table(:events, force: true) { |t| t.string :name }
  create_table(:users, force: true) do |t|
    t.string :switch
    t.bigint :event_id
    t.bigint :prefecture_id
    t.bigint :prefecture_sub_id
  end
  create_table(:tags, force: true) { |t| t.string :order }
  create_table(:user_tags, force: true) { |t| t.bigint :user_id; t.bigint :tag_id }
  create_table(:reviews, force: true) { |t| t.bigint :user_id }
  create_table(:schedules, force: true) { |t| t.bigint :user_id; t.string :day }
  add_index :schedules, :user_id
end

class Prefecture < ActiveRecord::Base; end
class Event < ActiveRecord::Base; end
class Tag < ActiveRecord::Base; end
class Review < ActiveRecord::Base; end
class Schedule < ActiveRecord::Base; end
class UserTag < ActiveRecord::Base
  belongs_to :tag
end
class User < ActiveRecord::Base
  paginates_per 20
  belongs_to :event
  belongs_to :prefecture
  belongs_to :prefecture_sub, class_name: 'Prefecture', optional: true
  has_many :reviews
  has_many :schedules
  has_many :user_tags
  has_many :tags, through: :user_tags
  # Exercise the exact association declaration used by the application.
  class_eval File.readlines(File.expand_path('../../app/models/user.rb', __dir__)).find { |line| line.include?('has_many :listing_tags,') }
end
require_relative '../../app/services/circle_listing_data'

class CircleListingDataTest < Minitest::Test
  def setup
    [UserTag, Review, Schedule, User, Tag, Event, Prefecture].each(&:delete_all)
    pref = Prefecture.create!(sort: 1, name: '東京')
    sub = Prefecture.create!(sort: 2, name: '神奈川')
    event = Event.create!(name: '運動')
    tags = ['2', '10', nil].map { |order| Tag.create!(order: order) }
    @users = 21.times.map do
      User.create!(switch: '募集中', event: event, prefecture: pref, prefecture_sub: sub)
    end
    UserTag.insert_all!(@users.flat_map { |u| tags.map { |t| { user_id: u.id, tag_id: t.id } } })
    Review.insert_all!(@users.flat_map { |u| Array.new(10) { { user_id: u.id } } })
    Schedule.insert_all!(@users.flat_map do |u|
      250.times.map { |i| { user_id: u.id, day: (Date.today + i - 50).iso8601 } }
    end)
  end

  def relation
    User.includes(:reviews, :schedules, :tags, :prefecture).order('prefectures.sort ASC', 'users.id ASC').page(1).per(20)
  end

  def capture
    sql = []
    records = Hash.new(0)
    query_listener = ->(*args) { p = args.last; sql << p[:sql] if p[:sql].match?(/\ASELECT/i) && p[:name] != 'SCHEMA' }
    record_listener = ->(*args) { p = args.last; records[p[:class_name]] += p[:record_count] }
    ActiveSupport::Notifications.subscribed(query_listener, 'sql.active_record') do
      ActiveSupport::Notifications.subscribed(record_listener, 'instantiation.active_record') { yield }
    end
    [sql, records]
  end

  def test_bounded_loading_and_query_count_does_not_grow_per_circle
    data = CircleListingData.new(relation)
    sql, records = capture do
      data.users.each do |user|
        assert_equal 10, data.review_count(user)
        assert_equal 2, data.schedules_for(user).size
        assert_equal ['10', '2', nil], user.listing_tags.map(&:order)
        assert_equal '東京', user.prefecture.name
        assert_equal '神奈川', user.prefecture_sub.name
        assert_equal '運動', user.event.name
      end
    end
    assert_equal 0, records['Review']
    assert_equal 40, records['Schedule']
    assert_operator sql.size, :<=, 10
    assert_equal 1, sql.count { |query| query.include?('CROSS JOIN LATERAL') }
    assert_equal 1, sql.count { |query| query.include?('COUNT(*)') && query.include?('reviews') }
    puts "Bounded list: #{sql.size} SELECTs, #{records['Schedule']} Schedule objects, #{records['Review']} Review objects"
  end

  def test_same_schedules_as_existing_queries_and_same_pagination
    data = CircleListingData.new(relation)
    assert_equal @users.first(20).map(&:id), data.users.map(&:id)
    assert_equal 21, data.users.total_count
    assert_equal 2, data.users.total_pages
    data.users.each do |user|
      expected = Schedule.where(user_id: user.id).where('day > ?', DateTime.yesterday).order(:day, :id).limit(2).pluck(:id)
      assert_equal expected, data.schedules_for(user).map(&:id)
    end
    second = CircleListingData.new(relation.page(2))
    assert_equal [@users.last.id], second.users.map(&:id)
    assert_equal 2, second.schedules_for(second.users.first).size
  end

  def test_no_reviews_no_schedules_and_closed_recruitment
    user = @users.first
    user.update!(switch: '募集停止')
    Review.where(user_id: user.id).delete_all
    data = CircleListingData.new(User.where(id: user.id))
    sql, = capture do
      assert_equal 0, data.review_count(data.users.first)
      assert_empty data.schedules_for(data.users.first)
    end
    refute sql.any? { |query| query.include?('CROSS JOIN LATERAL') }
    empty = CircleListingData.new(User.none)
    assert_empty empty.users
  end

  def test_original_preload_materializes_entire_history
    _, records = capture { User.includes(:reviews, :schedules, :tags, :prefecture).order(:id).page(1).load }
    assert_equal 5_000, records['Schedule']
    assert_equal 200, records['Review']
    puts "Original preload: #{records['Schedule']} Schedule objects, #{records['Review']} Review objects"
  end

  def test_both_haml_templates_compile_and_use_bounded_data
    %w[app/views/users/_users_list.html.haml app/views/circles/commons/_users_list.html.haml].each do |path|
      source = File.read(File.expand_path("../../#{path}", __dir__))
      RubyVM::InstructionSequence.compile(Haml::Engine.new.call(source))
      refute_match(/user\.(reviews|schedules|tags)\b|Prefecture\.find/, source)
      assert_includes source, 'listing_data.schedules_for(user)'
    end
  end
end
