# Standalone suite: uses installed gems and an in-memory database only.
# Does not boot the production app or load credentials, .env or fixtures.
ENV['RAILS_ENV'] = 'test'
require 'bundler/setup'
require 'logger'
require 'rails'
require 'action_controller/railtie'
require 'active_record'
require 'rack/attack'
require 'minitest/autorun'
require 'tmpdir'
require 'active_support/testing/time_helpers'

class SecurityTestApp < Rails::Application
  config.eager_load = false
  config.action_dispatch.show_exceptions = :none
  config.secret_key_base = 'test-only-key-never-used-outside-this-suite'
  config.logger = Logger.new(File::NULL)
  config.hosts.clear
end
Rails.application = SecurityTestApp.new
require_relative '../../config/initializers/cloudflare_proxy'
require_relative '../../app/controllers/concerns/spam_protection'
require_relative '../../lib/abuse_counter_store'
require_relative '../../lib/abuse_protection'
require 'rails/test_help'
abort 'Run this suite in a separate Ruby process' if defined?(::User)
ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table(:users) { |t| t.float :review_score; t.boolean :review_permit; t.string :switch; t.integer :admin_user_id; t.string :ng_account }
  create_table(:reviews) { |t| t.integer :user_id; t.integer :member_id; t.integer :review; t.string :ip; t.text :comment; t.string :nickname; t.string :age; t.string :gender; t.timestamps }
  create_table(:places) { |t| %i[facility price access reservation score].each { |k| t.float "average_#{k}" }; t.timestamps }
  create_table(:place_reviews) { |t| t.integer :place_id; t.integer :event_id; t.string :ip_address; t.text :comment; t.string :moderation_status, default: 'clear', null: false; %i[facility price access reservation average_score].each { |k| t.float k }; t.timestamps }
  create_table(:account_blocks) { |t| t.string :ip_address }
  create_table(:prefectures) { |t| t.string :name }
  create_table(:invalid_emails) { |t| t.string :email }
  create_table(:blogs) { |t| t.integer :user_id; t.string :title; t.text :content }
end
class ApplicationRecord < ActiveRecord::Base; self.abstract_class = true; end
class User < ApplicationRecord
  has_many :reviews
  has_many :blogs
  def admin_user; Struct.new(:email).new('owner@example.test'); end
  def publicly_visible?; true; end
end
class Place < ApplicationRecord
  has_many :place_reviews
  has_many :public_place_reviews, -> { where(moderation_status: 'clear') }, class_name: 'PlaceReview'
  def refresh_review_scores!
    averages = %i[facility reservation price access].to_h { |key| ["average_#{key}", public_place_reviews.average(key)&.to_f] }
    score = averages.values.all? ? averages.values.sum / 4.0 : nil
    update_columns(averages.merge('average_score' => score, 'updated_at' => Time.current))
  end
end
class Member < ApplicationRecord; end
class AccountBlock < ApplicationRecord; end
class Prefecture < ApplicationRecord; end
class InvalidEmail < ApplicationRecord; end
class Blog < ApplicationRecord
  belongs_to :user
  validates :title, presence: true
  validates :content, length: { minimum: 100 }
end
require_relative '../../app/models/review'
require_relative '../../app/models/place_review'
module Circlebook; end
class ApplicationController < ActionController::Base
  include SpamProtection
  # Rails recycles controller instance variables between requests. Keep the
  # test identity in the session, as the real authentication layer does.
  %i[current_member current_admin_user].each do |identity|
    define_method(identity) { session[identity] }
    define_method("#{identity}=") { |value| session[identity] = value }
  end
  def member_signed_in?; current_member.present?; end
  def admin_user_signed_in?; current_admin_user.present?; end
  def authenticate_admin_user!; head :unauthorized unless admin_user_signed_in?; end
  def cb_point(*); end
  def last_post(*); end
end
module Circles; class ApplicationController < ::ApplicationController; end; end
require_relative '../../app/controllers/reviews_controller'
require_relative '../../app/controllers/place_reviews_controller'
require_relative '../../app/controllers/circles/blogs_controller'
Rails.application.routes.draw do
  root to: 'reviews#all_reviews'
  resources :users do
    resources :reviews
  end
  scope :coat do
    resources :places do
      resources :place_reviews
    end
  end
  scope module: :circles do
    resources :circles do
      resources :blogs
    end
  end
  get '/blogs', to: 'circles/blogs#index'
end

ApplicationController.include Rails.application.routes.url_helpers

class SpamFormTest < Minitest::Test
  include ActiveSupport::Testing::TimeHelpers
  class Harness
    def self.helper_method(*); end
    include SpamProtection
    attr_accessor :params
    attr_reader :session, :response, :result
    def initialize
      @session = {}; @params = {}; @response = Struct.new(:headers).new({})
    end
    def render(**result); @result = result; end
  end
  def setup; @form = Harness.new; end
  def test_signed_session_bound_scoped_token
    token = @form.send(:spam_form_token, 'review:1')
    @form.params = { spam_form_token: token }
    assert @form.send(:verify_spam_form!, 'review:1')
    refute @form.send(:verify_spam_form!, 'review:2')
    other = Harness.new
    other.send(:spam_form_token, 'review:1')
    other.params = { spam_form_token: token }
    refute other.send(:verify_spam_form!, 'review:1')
  end
  def test_missing_malformed_honeypot_and_expired_tokens
    [nil, [], {}, 'x' * 3000, 'invalid'].each do |token|
      @form.params = { spam_form_token: token }
      refute @form.send(:verify_spam_form!, 'registration:member')
    end
    token = @form.send(:spam_form_token, 'registration:member')
    @form.params = { spam_form_token: token, contact_website: 'spam' }
    refute @form.send(:verify_spam_form!, 'registration:member')
    @form.params = { spam_form_token: token }
    travel 13.hours do
      refute @form.send(:verify_spam_form!, 'registration:member')
    end
  end
end

class AntiSpamRateTest < Minitest::Test
  include ActiveSupport::Testing::TimeHelpers
  def setup
    @dir = Dir.mktmpdir('anti-spam-test')
    Rack::Attack.clear_configuration
    AbuseProtection.configure(store: AbuseCounterStore.new(@dir), logger: Logger.new(File::NULL))
    load File.expand_path('../../config/initializers/posting_spam_protection.rb', __dir__)
    @app = ActionDispatch::RemoteIp.new(Rack::Attack.new(->(_env) { [200, {}, ['ok']] }),
                                      true, Rails.application.config.action_dispatch.trusted_proxies)
    travel_to Time.at((Time.now.to_i / 3600) * 3600 + 10)
  end
  def teardown
    travel_back
    FileUtils.remove_entry(@dir)
  end
  def request(path, method: 'POST', ip: '198.51.100.1', forwarded: nil)
    env = Rack::MockRequest.env_for(path, method: method)
    env['REMOTE_ADDR'] = ip
    env['HTTP_X_FORWARDED_FOR'] = forwarded if forwarded
    @app.call(env)
  end
  def test_registration_limits_shared_across_account_types_and_formats
    %w[/admin_users /members /exhibition_groups /members.json /members/].each { |p| assert_equal 200, request(p).first }
    5.times { assert_equal 200, request('/members').first }
    result = request('/admin_users')
    assert_equal 429, result.first
    assert_operator result[1]['Retry-After'].to_i, :>, 0
    assert_equal 200, request('/members', ip: '198.51.100.2').first
    assert_equal 200, request('/members', method: 'GET').first
    assert_equal 200, request('/members/sign_in').first
    travel 1.hour
    assert_equal 200, request('/members').first
  end
  def test_post_limits_cover_reviews_facilities_and_blog_edits
    5.times { assert_equal 200, request('/users/1/reviews').first }
    assert_equal 429, request('/coat/places/1/place_reviews').first
    assert_equal 429, request('/circles/1/blogs/2.json', method: 'PATCH').first
    assert_equal 200, request('/circles/1/blogs', method: 'GET').first
  end
  def test_encoded_and_repeated_slashes_cannot_bypass_limit
    10.times { assert_equal 200, request('/members').first }
    assert_equal 429, request('/%6dembers').first
    assert_equal 429, request('/members//').first
    assert_equal 429, request('/members.JSON').first
    assert_equal 429, request('/members.json-extra').first
  end
  def test_hourly_post_limit_survives_minute_windows
    6.times do
      5.times { assert_equal 200, request('/circles/1/blogs').first }
      travel 1.minute
    end
    assert_equal 429, request('/users/2/reviews').first
  end
  def test_spoofed_forwarded_prefix_does_not_rotate_identity
    10.times { |i| assert_equal 200, request('/members', ip: '127.0.0.1', forwarded: "203.0.113.#{i}, 198.51.100.7").first }
    assert_equal 429, request('/members', ip: '127.0.0.1', forwarded: '203.0.113.100, 198.51.100.7').first
  end
  def test_counters_are_atomic_across_processes
    workers = 4.times.map do
      fork do
        store = AbuseCounterStore.new(@dir)
        25.times { store.increment('parallel', 1, expires_in: 60) }
        exit! 0
      end
    end
    workers.each { |pid| Process.wait(pid); assert_predicate $?, :success? }
    assert_equal 101, Rack::Attack.cache.store.increment('parallel', 1, expires_in: 60)
  end

  def test_cloudflare_visitors_do_not_share_a_signup_counter
    10.times do
      assert_equal 200, request('/members', ip: '127.0.0.1',
                               forwarded: '198.51.100.7, 172.64.1.2, 10.0.0.5').first
    end
    assert_equal 429, request('/members', ip: '127.0.0.1',
                             forwarded: '203.0.113.100, 198.51.100.7, 172.64.1.3, 10.0.0.5').first
    assert_equal 200, request('/members', ip: '127.0.0.1',
                             forwarded: '198.51.100.8, 172.64.1.2, 10.0.0.5').first
  end

  def test_cloudflare_ipv6_visitors_have_separate_post_counters
    5.times do
      assert_equal 200, request('/users/1/reviews', ip: '127.0.0.1',
                               forwarded: '2001:db8::1, 2606:4700::1, 10.0.0.5').first
    end
    assert_equal 429, request('/users/1/reviews', ip: '127.0.0.1',
                             forwarded: '2001:db8::1, 2606:4700::2, 10.0.0.5').first
    assert_equal 200, request('/users/1/reviews', ip: '127.0.0.1',
                             forwarded: '2001:db8::2, 2606:4700::1, 10.0.0.5').first
  end

  def test_untrusted_cf_headers_do_not_change_the_visitor_identity
    env = Rack::MockRequest.env_for('/members', method: 'POST')
    env['REMOTE_ADDR'] = '127.0.0.1'
    env['HTTP_X_FORWARDED_FOR'] = '203.0.113.5, 198.51.100.7, 10.0.0.5'
    10.times do |i|
      assert_equal 200, @app.call(env.merge('HTTP_CF_CONNECTING_IP' => "203.0.113.#{i}")).first
    end
    assert_equal 429, @app.call(env.merge('HTTP_CF_CONNECTING_IP' => '203.0.113.200')).first
  end
end

class ReviewSubmissionTest < ActionController::TestCase
  tests ReviewsController
  setup do
    [Review, User, AccountBlock].each(&:delete_all)
    @user = User.create!(review_permit: true)
    @request.env['REMOTE_ADDR'] = '198.51.100.1'
    @controller.response = @response
    @token = @controller.send(:spam_form_token, "review:#{@user.id}")
  end
  def submission(**options)
    { user_id: @user.id, spam_form_token: @token, review: { review: 1, comment: '参加して楽しかったです。', ip: 'forged' } }.merge(options)
  end
  test 'missing form proof creates nothing' do
    assert_no_difference('Review.count') { post :create, params: submission(spam_form_token: nil) }
    assert_response :unprocessable_entity
  end
  test 'valid review saved once with server ip and aggregate' do
    assert_difference('Review.count', 1) { post :create, params: submission }
    assert_response :redirect
    assert_equal '198.51.100.1', Review.last.ip
    assert_equal 5.0, @user.reload.review_score
    assert_no_difference('Review.count') { post :create, params: submission }
    assert_response :conflict
  end
  test 'invalid first or later review never alters another review or score' do
    assert_no_difference('Review.count') { post :create, params: submission(review: { review: 1, comment: '短い' }) }
    original = Review.create!(user: @user, review: 0, comment: 'もう少し改善してほしいです。', ip: '198.51.100.9')
    @user.update!(review_score: 0)
    assert_no_difference('Review.count') { post :create, params: submission(review: { review: 7, comment: '不正な評価の投稿です。' }) }
    assert_equal '198.51.100.9', original.reload.ip
    assert_equal 0, @user.reload.review_score
  end
  test 'disabled reviews and blocked ip are enforced on direct post' do
    @user.update!(review_permit: false)
    assert_no_difference('Review.count') { post :create, params: submission }
    assert_response :forbidden
    @user.update!(review_permit: true)
    AccountBlock.create!(ip_address: '198.51.100.1')
    assert_no_difference('Review.count') { post :create, params: submission }
    assert_response :forbidden
  end
  test 'anonymous visitor cannot update or delete existing review' do
    review = Review.create!(user: @user, member_id: 4, review: 1, comment: '参加して楽しかったです。')
    patch :update, params: { user_id: @user.id, id: review.id, review: { comment: '勝手に書き換えた内容です。' } }
    assert_response :forbidden
    assert_equal '参加して楽しかったです。', review.reload.comment
    assert_no_difference('Review.count') { delete :destroy, params: { user_id: @user.id, id: review.id } }
    assert_response :forbidden
  end
  test 'member cannot post twice by changing ip and cannot use another parent' do
    @controller.current_member = Struct.new(:id).new(4)
    review = Review.create!(user: @user, member_id: 4, review: 1, comment: '参加して楽しかったです。', ip: '198.51.100.9')
    assert_no_difference('Review.count') { post :create, params: submission }
    assert_response :conflict
    other = User.create!(review_permit: true)
    assert_raises(ActiveRecord::RecordNotFound) do
      delete :destroy, params: { user_id: other.id, id: review.id }
    end
    assert Review.exists?(review.id)
  end
  test 'review owner can edit and delete while other member cannot' do
    review = Review.create!(user: @user, member_id: 4, review: 1, comment: '参加して楽しかったです。')
    @controller.current_member = Struct.new(:id).new(5)
    delete :destroy, params: { user_id: @user.id, id: review.id }
    assert_response :forbidden
    @controller.current_member = Struct.new(:id).new(4)
    patch :update, params: { user_id: @user.id, id: review.id, review: { review: 0, comment: '改善してほしい点があります。' } }
    assert_response :redirect
    assert_equal 0, @user.reload.review_score
    assert_difference('Review.count', -1) { delete :destroy, params: { user_id: @user.id, id: review.id } }
  end
end

class PlaceReviewSubmissionTest < ActionController::TestCase
  tests PlaceReviewsController
  setup do
    [PlaceReview, Place, AccountBlock].each(&:delete_all)
    @place = Place.create!
    @request.env['REMOTE_ADDR'] = '198.51.100.1'
    @controller.response = @response
    @token = @controller.send(:spam_form_token, "place_review:#{@place.id}")
  end
  def submission(**changes)
    { place_id: @place.id, spam_form_token: @token,
      place_review: { facility: 5, reservation: 4, price: 3, access: 2, comment: '設備がきれいで使いやすいです。', ip_address: 'forged', average_score: 100 }.merge(changes) }
  end
  test 'valid review uses server ip and computed scores and rejects duplicate' do
    assert_difference('PlaceReview.count', 1) { post :create, params: submission }
    assert_equal '198.51.100.1', PlaceReview.last.ip_address
    assert_equal 3.5, PlaceReview.last.average_score
    assert_equal 3.5, @place.reload.average_score
    assert_no_difference('PlaceReview.count') { post :create, params: submission }
    assert_response :conflict
  end
  test 'invalid scores and missing ratings never persist' do
    [nil, -1, 6, 'NaN', 'abc'].each do |rating|
      assert_no_difference('PlaceReview.count') { post :create, params: submission(facility: rating) }
      assert_nil @place.reload.average_score
    end
  end
  test 'uppercase and www links and long comments are rejected' do
    ['HTTPS://spam.example', 'www.spam.example', 'あ' * 2001].each do |comment|
      assert_no_difference('PlaceReview.count') { post :create, params: submission(comment: comment) }
    end
  end
  test 'only master can remove facility spam and ratings are recalculated' do
    review = @place.place_reviews.create!(facility: 5, reservation: 5, price: 5, access: 5, comment: '設備がきれいで使いやすいです。')
    assert_no_difference('PlaceReview.count') { delete :destroy, params: { place_id: @place.id, id: review.id } }
    assert_response :forbidden
    @controller.current_admin_user = Struct.new(:master_account?).new(false)
    assert_no_difference('PlaceReview.count') { delete :destroy, params: { place_id: @place.id, id: review.id } }
    assert_response :forbidden
    @controller.current_admin_user = Struct.new(:master_account?).new(true)
    other = Place.create!
    assert_raises(ActiveRecord::RecordNotFound) do
      delete :destroy, params: { place_id: other.id, id: review.id }
    end
    assert_difference('PlaceReview.count', -1) { delete :destroy, params: { place_id: @place.id, id: review.id } }
    assert_nil @place.reload.average_score
  end
  test 'missing token and blocked ip cannot write' do
    assert_no_difference('PlaceReview.count') { post :create, params: submission.merge(spam_form_token: nil) }
    assert_response :unprocessable_entity
    AccountBlock.create!(ip_address: '198.51.100.1')
    assert_no_difference('PlaceReview.count') { post :create, params: submission }
    assert_response :forbidden
  end
  test 'non-Japanese comments wait for review and do not affect ratings' do
    assert_difference('PlaceReview.count', 1) do
      post :create, params: submission(comment: 'Automated facility comment in English')
    end
    assert_equal 'review', PlaceReview.last.moderation_status
    assert_nil @place.reload.average_score
    assert_empty @place.public_place_reviews
  end
  test 'rapid submissions across facilities are limited' do
    3.times do |index|
      @place = Place.create!
      @token = @controller.send(:spam_form_token, "place_review:#{@place.id}")
      post :create, params: submission(comment: "設備がきれいで使いやすいです。#{index}")
      assert_response :redirect
    end
    @place = Place.create!
    @token = @controller.send(:spam_form_token, "place_review:#{@place.id}")
    assert_no_difference('PlaceReview.count') { post :create, params: submission(comment: '設備がきれいで使いやすいです。') }
    assert_response :too_many_requests
  end
end

class BlogSubmissionTest < ActionController::TestCase
  tests Circles::BlogsController
  Account = Struct.new(:id, :check) do
    def master_account?; false; end
    def users; User.where(admin_user_id: id); end
  end
  setup do
    [Blog, User].each(&:delete_all)
    @user = User.create!(admin_user_id: 2)
    @controller.response = @response
    @token = @controller.send(:spam_form_token, "blog:#{@user.id}")
  end
  def submission
    { circle_id: @user.id, spam_form_token: @token, blog: { title: '活動記録', content: '楽しく活動しました。' * 20 } }
  end
  test 'anonymous and wrong owner cannot publish' do
    assert_no_difference('Blog.count') { post :create, params: submission }
    assert_response :unauthorized
    @controller.current_admin_user = Account.new(3, nil)
    assert_no_difference('Blog.count') { post :create, params: submission }
    assert_response :forbidden
  end
  test 'blocked owners and missing form proof cannot publish' do
    @controller.current_admin_user = Account.new(2, 1)
    assert_no_difference('Blog.count') { post :create, params: submission }
    assert_response :forbidden
    @controller.current_admin_user.check = nil
    assert_no_difference('Blog.count') { post :create, params: submission.merge(spam_form_token: nil) }
    assert_response :unprocessable_entity
    @user.update!(ng_account: 'NG')
    assert_no_difference('Blog.count') { post :create, params: submission }
    assert_response :forbidden
  end
  test 'owner with valid proof creates exactly once' do
    @controller.current_admin_user = Account.new(2, nil)
    assert_difference('Blog.count', 1) { post :create, params: submission }
    assert_response :redirect
  end
end
