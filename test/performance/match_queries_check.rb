# Uses only the same isolated disposable PostgreSQL cluster as the listing check.
# This also runs the existing bounded-list regression suite.
require_relative 'circle_listing_data_check'
require 'action_controller'

ActiveRecord::Schema.define do
  add_column :events, :ruby, :string
  add_column :prefectures, :kana, :string
  add_column :users, :name, :string
  create_table(:matches, force: true) do |t|
    t.bigint :user_id
    t.datetime :updated_at
  end
end

class Match < ActiveRecord::Base
  belongs_to :user
  paginates_per 10
end
class ApplicationController < ActionController::Base; end
require_relative '../../app/controllers/matches_controller'

class MatchQueriesTest < Minitest::Test
  def setup
    [Match, UserTag, Review, Schedule, User, Event, Prefecture].each(&:delete_all)
    @event = Event.create!(name: '運動', ruby: 'sport')
    @pref = Prefecture.create!(name: '東京', kana: 'tokyo')
    @users = 25.times.map do |i|
      user = User.create!(event: @event, prefecture: @pref, name: "test #{i}")
      Match.create!(id: user.id, user: user, updated_at: Time.at(1000 + i))
      user
    end
    other = User.create!(event: Event.create!(name: '別種目', ruby: 'other'),
                         prefecture: Prefecture.create!(name: '別地域', kana: 'other'))
    Match.create!(id: other.id, user: other, updated_at: Time.at(1))
  end

  def test_filter_results_pagination_and_bounded_user_instantiation
    [:event, :prefecture, :event_prefecture].each do |action|
      controller = MatchesController.new
      controller.params = ActionController::Parameters.new(ruby: 'sport', kana: 'tokyo', page: '1')
      statements = []
      users_loaded = 0
      query_listener = ->(*args) { p = args.last; statements << p[:sql] if p[:sql].start_with?('SELECT') && p[:name] != 'SCHEMA' }
      record_listener = ->(*args) { p = args.last; users_loaded += p[:record_count] if p[:class_name] == 'User' }
      ActiveSupport::Notifications.subscribed(query_listener, 'sql.active_record') do
        ActiveSupport::Notifications.subscribed(record_listener, 'instantiation.active_record') do
          controller.public_send(action)
          matches = controller.instance_variable_get(:@matches)
          assert_equal @users.reverse.first(10).map(&:id), matches.map(&:id)
          assert_equal 25, matches.total_count
          matches.each do |match|
            assert_equal '運動', match.user.event.name
            assert_equal '東京', match.user.prefecture.name
          end
        end
      end
      assert_equal 10, users_loaded
      assert_operator statements.size, :<=, 7
      assert statements.any? { |sql| sql.include?('IN (SELECT "users"."id"') }
    end
  end

  def test_index_and_show_preserve_order_and_exclude_current_match
    controller = MatchesController.new
    controller.params = ActionController::Parameters.new(page: '1')
    controller.index
    assert_equal @users.reverse.first(10).map(&:id), controller.instance_variable_get(:@matches).map(&:id)
    controller.params = ActionController::Parameters.new(id: @users.first.id)
    controller.show
    assert_equal @users.drop(1).reverse.map(&:id), controller.instance_variable_get(:@matches).map(&:id)
    assert_equal @event, controller.instance_variable_get(:@event)
    assert_nil controller.instance_variable_get(:@sub_prefecture)
  end
end
