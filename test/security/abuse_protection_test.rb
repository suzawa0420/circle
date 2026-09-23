# Run independently of Rails boot / production credentials / database.
require 'bundler/setup'
require 'minitest/autorun'
require 'active_support/all'
require 'action_dispatch'
require 'action_controller'
require 'rack/attack'
require 'tmpdir'
require 'stringio'
require_relative '../../lib/abuse_counter_store'
require_relative '../../lib/abuse_protection'
require_relative '../../app/controllers/concerns/registration_bot_guard'

class AbuseProtectionTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir('circle-abuse-test')
    @log = StringIO.new
    @store = AbuseCounterStore.new(@dir, logger: Logger.new(@log))
    Rack::Attack.clear_configuration
    AbuseProtection.configure(store: @store, logger: Logger.new(@log))
    @app = ActionDispatch::RemoteIp.new(Rack::Attack.new(->(_env) { [200, {}, ['ok']] }))
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def request(path, method: 'POST', ip: '203.0.113.7', forwarded: nil)
    env = Rack::MockRequest.env_for(path, method: method)
    env['REMOTE_ADDR'] = forwarded ? '172.26.8.237' : ip
    env['HTTP_X_FORWARDED_FOR'] = forwarded if forwarded
    @app.call(env)
  end

  def test_registration_limit_shared_across_all_account_types_and_formats
    10.times { |i| assert_equal 200, request("/#{AbuseProtection::ACCOUNTS[i % 3]}")[0] }
    status, headers, = request('/members.json')
    assert_equal 429, status
    assert_operator headers['Retry-After'].to_i, :>, 0
    assert_equal 'no-store', headers['Cache-Control']
    assert_equal 429, request('/%6dembers/')[0]
    assert_equal 200, request('/members', ip: '203.0.113.8')[0]
    assert_equal 200, request('/members', method: 'PATCH')[0]
  end

  def test_public_pages_and_health_are_unaffected
    80.times { assert_equal 200, request('/circles', method: 'GET')[0] }
    assert_equal 200, request('/health', method: 'GET')[0]
    assert_empty Dir.children(@dir)
  end

  def test_login_and_password_limits_are_separate
    60.times { assert_equal 200, request('/members/sign_in')[0] }
    assert_equal 429, request('/admin_users/sign_in')[0]
    10.times { assert_equal 200, request('/members/password')[0] }
    assert_equal 429, request('/exhibition_groups/password')[0]
    assert_equal 200, request('/members')[0]
  end

  def test_spoofed_forwarded_prefix_cannot_reset_counter
    10.times { |i| assert_equal 200, request('/members', forwarded: "198.51.100.#{i}, 203.0.113.7")[0] }
    assert_equal 429, request('/members', forwarded: '198.51.100.100, 203.0.113.7')[0]
    assert_equal 200, request('/members', forwarded: '203.0.113.8')[0]
  end

  def test_store_is_shared_and_atomic_across_processes
    children = 4.times.map do
      fork do
        25.times { AbuseCounterStore.new(@dir).increment('same-key', 1, expires_in: 60) }
        exit! 0
      end
    end
    children.each { |pid| assert Process.wait2(pid)[1].success? }
    assert_equal 101, @store.increment('same-key', 1, expires_in: 60)
  end

  def test_expired_values_and_privacy
    assert_equal 1, @store.increment('sensitive@example.com', 1, expires_in: -1)
    assert_equal 1, @store.increment('sensitive@example.com', 1, expires_in: 60)
    refute_includes File.read(Dir[File.join(@dir, '*.json')].first), 'sensitive'
    11.times { request('/members') }
    refute_includes @log.string, '203.0.113.7'
    assert_includes @log.string, 'account/signup'
  end

  def test_corrupted_storage_recovers_and_disk_failure_does_not_break_login
    @store.increment('key', 1, expires_in: 60)
    File.write(Dir[File.join(@dir, '*.json')].first, '{')
    assert_equal 1, @store.increment('key', 1, expires_in: 60)
    assert_equal 2, @store.increment('key', 1, expires_in: 60)
    invalid_directory = File.join(@dir, 'not-a-directory')
    File.write(invalid_directory, '')
    assert_equal 1, AbuseCounterStore.new(invalid_directory).increment('key', 1, expires_in: 60)
  end

  class RegistrationController < ActionController::Base
    include RegistrationBotGuard
    def create
      render plain: 'created', status: :created
    end
    def update
      render plain: 'updated'
    end
  end

  def test_real_controller_callback_stops_create_but_not_account_update
    Object.const_set(:Rails, Module.new) unless defined?(Rails)
    Rails.define_singleton_method(:logger) { Logger.new(StringIO.new) }
    env = Rack::MockRequest.env_for('/members', method: 'POST', params: { registration_website: 'spam' })
    assert_equal 422, RegistrationController.action(:create).call(env)[0]
    env = Rack::MockRequest.env_for('/members', method: 'POST', params: { registration_website: '' })
    assert_equal 201, RegistrationController.action(:create).call(env)[0]
    env = Rack::MockRequest.env_for('/members', method: 'PATCH', params: { registration_website: 'spam' })
    assert_equal 200, RegistrationController.action(:update).call(env)[0]
  end

  def test_production_initializers_load_on_installed_rails_and_log_only_slow_timings
    Object.const_set(:Rails, Module.new) unless defined?(Rails)
    output = StringIO.new
    root = Pathname.new(File.expand_path('../..', __dir__))
    Rails.define_singleton_method(:root) { root }
    Rails.define_singleton_method(:logger) { Logger.new(output) }
    load root.join('config/initializers/rack_attack.rb')
    load root.join('config/initializers/slow_request_logging.rb')
    assert_instance_of AbuseCounterStore, Rack::Attack.cache.store
    payload = { controller: 'HomeController', action: 'index', status: 200, db_runtime: 12,
                params: { password: 'do-not-log' }, path: '/?private=yes' }
    ActiveSupport::Notifications.publish('process_action.action_controller', Time.at(0), Time.at(1), 'test', payload)
    assert_empty output.string
    ActiveSupport::Notifications.publish('process_action.action_controller', Time.at(0), Time.at(3), 'test', payload)
    assert_includes output.string, 'duration=3000.0ms'
    assert_includes output.string, 'db=12.0ms'
    refute_includes output.string, 'do-not-log'
    refute_includes output.string, 'private=yes'
  end

  class GuardHarness
    def self.prepend_before_action(*); end
    include RegistrationBotGuard
    attr_accessor :params, :rendered
    def initialize(value)
      @params = { registration_website: value }
    end
    def response
      @response ||= Struct.new(:headers).new({})
    end
    def render(**args)
      @rendered = args
    end
  end

  def test_honeypot_accepts_empty_and_rejects_automated_values
    Object.const_set(:Rails, Module.new) unless defined?(Rails)
    Rails.define_singleton_method(:logger) { Logger.new(StringIO.new) }
    [nil, ''].each do |value|
      guard = GuardHarness.new(value)
      guard.send(:reject_automated_registration)
      assert_nil guard.rendered
    end
    guard = GuardHarness.new('https://spam.invalid')
    guard.send(:reject_automated_registration)
    assert_equal :unprocessable_entity, guard.rendered[:status]
  end
end
