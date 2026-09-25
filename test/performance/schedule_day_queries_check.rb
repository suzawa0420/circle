# Uses only the guarded disposable PostgreSQL database and synthetic fixtures.
require_relative 'search_queries_check'
require_relative '../../app/controllers/schedules_controller'

class Schedule
  belongs_to :user
end

class ScheduleDayQueriesTest < SearchQueriesTest
  def test_day_filters_keep_order_pages_and_count_without_loading_all_users
    @users.each do |user|
      2.times { Schedule.create!(user_id: user.id, day: '2026-09-26') }
      Schedule.create!(user_id: user.id, day: '2026-09-27')
    end
    Schedule.create!(user_id: @nationwide.id, day: '2026-09-26')
    Schedule.create!(user_id: nil, day: '2026-09-26')
    [{}, { event: 'basketball' }, { pref: 'tokyo' },
     { event: 'basketball', pref: 'tokyo' }].each do |filters|
      [1, 2, 5, 6].each do |page|
        controller = SchedulesController.new
        controller.params = ActionController::Parameters.new(
          { year: '2026', month: '09', day: '26', page: page }.merge(filters))
        controller.instance_variable_set(:@wdays, %w[日 月 火 水 木 金 土])
        sql, records = capture { controller.day }
        assert_equal 0, records['User'], 'Filtering must not materialize matching circles'
        refute sql.any? { |statement| statement.include?('FROM "users"') }

        old_users = User.all
        old_users = old_users.event(@event.id) if filters[:event]
        old_users = old_users.prefecture(@pref.id) if filters[:pref]
        expected = Schedule.joins(:user).where(day: '2026-09-26')
        expected = expected.where(user_id: old_users.map(&:id)) unless filters.empty?
        expected = expected.order(day: :asc).order('users.last_post desc').page(page).per(20)
        actual = controller.instance_variable_get(:@schedules).except(:includes)
        # Multiple schedules for one user have equal sort keys; compare the
        # user sequence and selected IDs without imposing a new tie-breaker.
        assert_equal expected.pluck(:user_id), actual.pluck(:user_id)
        assert_equal expected.total_count, actual.total_count
        assert_equal expected.except(:limit, :offset, :order).pluck(:id).sort,
          actual.except(:limit, :offset, :order).pluck(:id).sort
        if filters.any?
          assert_kind_of ActiveRecord::Relation, controller.instance_variable_get(:@user_ids)
        end
      end
    end
    old_queries, old_records = capture { User.event(@event.id).map(&:id) }
    new_queries, new_records = capture { User.event(@event.id).select(:id) }
    assert_operator old_records['User'], :>=, 45
    assert_equal 0, new_records['User']
    assert_equal 1, old_queries.length
    assert_empty new_queries
    puts "Day filter: #{old_records['User']} User objects -> 0; preparation SELECTs 1 -> 0"
  end
end
