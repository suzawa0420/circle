# Synthetic PostgreSQL only; inherits the disposable-socket guard and real scopes.
require_relative 'search_queries_check'
require 'haml/template'

ActiveRecord::Schema.define do
  create_table(:blogs, force: true) do |t|
    t.bigint :user_id
    t.string :moderation_status
    t.datetime :created_at
  end
  add_index :blogs, :user_id
end
class Blog < ActiveRecord::Base
  source = File.read(File.expand_path('../../app/models/blog.rb', __dir__))
  class_eval(source.lines.find { |line| line.include?('scope :publicly_visible,') })
end
class User
  has_many :blogs
end

# Exercise the production partial with real relations. Omit only link interiors
# (image/upload helpers); record destinations to verify ordering and visibility.
class CircleRelatedContentView
  attr_reader :links, :ads
  def initialize(user, users)
    @user, @users = user, users
    @links, @ads = [], 0
    user.event # Do not include the heading's association lookup in the measurement.
  end

  def circle_blog_path(user_id, id); "/circles/#{user_id}/blogs/#{id}"; end
  def circle_path(id); "/circles/#{id}"; end
  def link_to(path)
    @links << path
    ''
  end
  def render(path)
    raise "Unexpected partial" unless path == '/layouts/ad_square'
    @ads += 1
    ''
  end
end

class SearchQueriesTest
  def render_related(user, relation)
    view = CircleRelatedContentView.new(user, relation)
    queries = []
    instantiated = Hash.new(0)
    sql_listener = ->(*args) do
      p = args.last
      queries << p[:sql] if p[:sql].match?(/\ASELECT/i) && p[:name] != 'SCHEMA'
    end
    record_listener = ->(*args) do
      p = args.last
      instantiated[p[:class_name]] += p[:record_count]
    end
    path = File.expand_path('../../app/views/circles/circles/_related_content.html.haml', __dir__)
    ActiveSupport::Notifications.subscribed(sql_listener, 'sql.active_record') do
      ActiveSupport::Notifications.subscribed(record_listener, 'instantiation.active_record') do
        Haml::Template.new(path).render(view)
      end
    end
    [view, queries, instantiated]
  end

  def test_detail_loads_only_five_visible_blogs_and_five_related_circles_without_counts
    Blog.delete_all
    user = @users.first
    Blog.insert_all!(100.times.map { |i| { user_id: user.id, moderation_status: 'clear', created_at: Time.at(1000 + i) } })
    Blog.create!(user_id: user.id, moderation_status: 'review', created_at: Time.at(9999))
    expected_blogs = Blog.where(moderation_status: 'clear').order(created_at: :desc).limit(5).pluck(:id)
    related = User.publicly_visible.where.not(id: user.id).order(id: :desc).limit(5)
    expected_related = related.pluck(:id)
    view, queries, records = render_related(user, related)
    assert_equal expected_blogs.map { |id| "/circles/#{user.id}/blogs/#{id}" } + expected_related.map { |id| "/circles/#{id}" }, view.links
    assert_equal 1, view.ads
    assert_equal 2, queries.size
    refute queries.any? { |sql| sql.match?(/COUNT\(|SELECT 1 AS one/i) }
    assert_equal 5, records['Blog']
    assert_equal 5, records['User']
    puts "Circle detail related content: #{queries.size} SELECTs; #{records['Blog']} Blog / #{records['User']} User objects; no COUNT"
  end

  def test_detail_ad_thresholds_empty_results_and_live_moderation
    user = @users.first
    [[0, 0], [2, 0], [3, 0], [0, 2], [0, 3]].each do |blog_count, circle_count|
      Blog.delete_all
      blog_count.times { |i| Blog.create!(user_id: user.id, moderation_status: 'clear', created_at: Time.at(i)) }
      view, = render_related(user, User.publicly_visible.where(id: @users.drop(1).first(circle_count).map(&:id)).limit(5))
      assert_equal blog_count + circle_count, view.links.size
      assert_equal(blog_count >= 3 || circle_count >= 3 ? 1 : 0, view.ads)
    end
    Blog.create!(user_id: user.id, moderation_status: 'clear', created_at: Time.at(500))
    @admin.update!(check: AdminUser::SHADOW_BANNED_CHECK)
    view, = render_related(user, User.publicly_visible.limit(5))
    assert_empty view.links
    assert_equal 0, view.ads
  end
end
