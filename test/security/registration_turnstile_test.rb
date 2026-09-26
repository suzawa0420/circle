# Standalone: no Rails application boot, real credentials, DB or network.
require 'bundler/setup'
require 'minitest/autorun'
require 'minitest/mock'
require 'active_support/all'
require 'action_controller'
require 'active_model'
require 'stringio'
require 'tmpdir'
require 'haml'
require 'yaml'
require_relative '../../lib/registration_turnstile'
require_relative '../../lib/turnstile_configuration_writer'
require_relative '../../lib/turnstile_form_readiness'
require_relative '../../app/controllers/concerns/registration_turnstile_guard'
require_relative '../../app/controllers/concerns/registration_bot_guard'

class RegistrationTurnstileTest < Minitest::Test
  DUMMY_SITE = 'dummy-public-site-key'
  DUMMY_SECRET = 'dummy-private-key-not-real'
  ROOT = File.expand_path('../..', __dir__)

  def setup
    RegistrationTurnstile.configure(site_key: DUMMY_SITE, secret_key: DUMMY_SECRET, required: true)
    @log = StringIO.new
    Object.const_set(:Rails, Module.new) unless defined?(Rails)
    logger = Logger.new(@log)
    Rails.define_singleton_method(:logger) { logger }
  end

  def teardown
    RegistrationTurnstile.configure
  end

  def success
    { 'success' => true, 'hostname' => 'circle-book.com', 'action' => 'registration' }
  end

  def test_success_requires_boolean_hostname_and_action
    [success, success.merge('hostname' => 'www.circle-book.com')].each do |result|
      RegistrationTurnstile.stub(:exchange, result) { assert_equal :accepted, RegistrationTurnstile.verify('dummy-token') }
    end
    [{ 'success' => true }, success.merge('success' => 'true'), success.merge('action' => 'login'),
     success.merge('hostname' => 'attacker.invalid'), success.merge('hostname' => 'circle-book.com.attacker.invalid'),
     { 'success' => false, 'error-codes' => ['timeout-or-duplicate'] }].each do |result|
      RegistrationTurnstile.stub(:exchange, result) { assert_equal :rejected, RegistrationTurnstile.verify('dummy-token') }
    end
  end

  def test_invalid_tokens_never_contact_cloudflare
    RegistrationTurnstile.stub(:exchange, ->(*) { flunk 'Unexpected network request' }) do
      [nil, '', '  ', [], {}, 'a' * 2049].each do |token|
        assert_equal :rejected, RegistrationTurnstile.verify(token)
      end
    end
  end

  def test_outages_are_closed_without_raising_or_exposing_details
    [Timeout::Error, SocketError, OpenSSL::SSL::SSLError, JSON::ParserError, EOFError].each do |error|
      RegistrationTurnstile.stub(:exchange, ->(*) { raise error, DUMMY_SECRET }) do
        assert_equal :unavailable, RegistrationTurnstile.verify('dummy-token')
      end
    end
    [nil, [], { 'success' => false, 'error-codes' => ['internal-error'] },
     { 'success' => false, 'error-codes' => ['invalid-input-secret'] }].each do |result|
      RegistrationTurnstile.stub(:exchange, result) { assert_equal :unavailable, RegistrationTurnstile.verify('dummy-token') }
    end
    assert_empty @log.string
  end

  def test_missing_or_partial_configuration_fails_closed_in_production
    RegistrationTurnstile.configure(required: true)
    assert_nil RegistrationTurnstile.site_key
    assert_equal :unavailable, RegistrationTurnstile.verify('dummy-token')
    RegistrationTurnstile.configure(site_key: DUMMY_SITE)
    assert RegistrationTurnstile.required?
    assert_equal :unavailable, RegistrationTurnstile.verify('dummy-token')
    RegistrationTurnstile.configure
    refute RegistrationTurnstile.required?
    assert_equal :accepted, RegistrationTurnstile.verify(nil)
  end

  class HTTPDouble
    attr_accessor :use_ssl, :verify_mode, :open_timeout, :read_timeout, :write_timeout, :max_retries
    attr_reader :request_value
    def initialize(response)
      @response = response
    end
    def request(value)
      @request_value = value
      @response
    end
  end

  def test_real_transport_encodes_token_uses_tls_and_limits_wait
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.instance_variable_set(:@read, true)
    response.body = JSON.generate(success)
    http = HTTPDouble.new(response)
    factory = lambda do |host, port, proxy|
      assert_equal 'challenges.cloudflare.com', host
      assert_equal 443, port
      assert_nil proxy
      http
    end
    Net::HTTP.stub(:new, factory) do
      assert_equal :accepted, RegistrationTurnstile.verify('dummy-token+&=')
    end
    assert http.use_ssl
    assert_equal OpenSSL::SSL::VERIFY_PEER, http.verify_mode
    assert_equal 2, http.open_timeout
    assert_equal 3, http.read_timeout
    assert_equal 3, http.write_timeout
    assert_equal 0, http.max_retries
    assert_equal '/turnstile/v0/siteverify', http.request_value.path
    assert_equal({ 'secret' => DUMMY_SECRET, 'response' => 'dummy-token+&=' }, URI.decode_www_form(http.request_value.body).to_h)
  end

  def test_transport_does_not_follow_redirects_or_accept_bad_responses
    [[Net::HTTPFound, '302', '{}'], [Net::HTTPBadGateway, '502', '{}'],
     [Net::HTTPOK, '200', '<html>error</html>'], [Net::HTTPOK, '200', 'x' * 16_385]].each do |klass, code, body|
      response = klass.new('1.1', code, '')
      response.instance_variable_set(:@read, true)
      response.body = body
      Net::HTTP.stub(:new, HTTPDouble.new(response)) do
        assert_equal :unavailable, RegistrationTurnstile.verify('dummy-token')
      end
    end
  end

  class Resource
    include ActiveModel::Model
    attr_accessor :email, :password, :password_confirmation
  end

  class RegistrationsController < ActionController::Base
    include RegistrationBotGuard
    include RegistrationTurnstileGuard
    attr_reader :resource
    def create
      render plain: 'created', status: :created
    end
    def new
      render plain: 'registration form'
    end
    def update
      render plain: 'updated'
    end
    def sign_up_params
      params.require(:member).permit(:email, :password, :password_confirmation)
    end
    def build_resource(values)
      @resource = Resource.new(values)
    end
    def clean_up_passwords(value)
      value.password = value.password_confirmation = nil
    end
    def set_minimum_password_length
      @minimum_password_length = 6
    end
    def render(*args, **options)
      if args.first == :new
        super(plain: [resource.email, resource.password, resource.password_confirmation,
                      resource.errors.full_messages.join(' ')].join('|'), status: options[:status])
      else
        super
      end
    end
  end

  def dispatch(action = :create, token: 'dummy-token', honeypot: '', accept: 'text/html')
    params = { 'member' => { 'email' => 'dummy@example.invalid', 'password' => 'dummy-password',
                            'password_confirmation' => 'dummy-password' },
               'cf-turnstile-response' => token, 'registration_website' => honeypot }
    env = Rack::MockRequest.env_for('/members', method: action == :new ? 'GET' : 'POST', params: params)
    env['HTTP_ACCEPT'] = accept
    status, headers, body = RegistrationsController.action(action).call(env)
    text = ''
    body.each { |part| text << part }
    [status, headers, text]
  end

  def test_controller_blocks_create_preserves_email_clears_password_and_never_logs_token
    RegistrationTurnstile.stub(:exchange, { 'success' => false }) do
      status, headers, body = dispatch
      assert_equal 422, status
      assert_includes headers['Cache-Control'], 'no-store'
      assert_includes body, 'dummy@example.invalid'
      assert_includes body, '認証を確認できませんでした'
      refute_includes body, 'dummy-password'
      refute_includes body, 'created'
    end
    %w[dummy-token dummy-password dummy@example.invalid].each { |value| refute_includes @log.string, value }
    refute_includes @log.string, DUMMY_SECRET
    assert_includes @log.string, '[Turnstile] registration rejected'
  end

  def test_controller_allows_verified_registration_and_never_checks_update_or_get
    RegistrationTurnstile.stub(:exchange, success) { assert_equal 201, dispatch[0] }
    RegistrationTurnstile.stub(:exchange, ->(*) { flunk 'Unexpected validation' }) do
      assert_equal 200, dispatch(:update)[0]
      status, headers, = dispatch(:new)
      assert_equal 200, status
      assert_includes headers['Cache-Control'], 'no-store'
      assert_equal 422, dispatch(:create, honeypot: 'spam')[0]
      assert_equal 422, dispatch(:create, token: nil)[0]
    end
  end

  def test_controller_outage_renders_retryable_503_instead_of_creating_account
    RegistrationTurnstile.stub(:exchange, nil) do
      status, _, body = dispatch
      assert_equal 503, status
      assert_includes body, '少し時間をおいて'
      refute_includes body, 'created'
    end
  end

  def test_non_html_requests_are_rejected_without_missing_template_errors
    status, _, body = dispatch(token: nil, accept: 'application/json')
    assert_equal 422, status
    assert_includes body, '認証を確認できませんでした'
    refute_includes body, 'created'
  end

  def test_initializer_and_parameter_filter_load_without_real_files_or_rails_boot
    root = Pathname.new(ROOT)
    Rails.define_singleton_method(:root) { root }
    Rails.define_singleton_method(:env) { ActiveSupport::StringInquirer.new('production') }
    configuration = Struct.new(:filter_parameters).new([])
    application = Struct.new(:config).new(configuration)
    Rails.define_singleton_method(:application) { application }
    loader = lambda do |production:, path:|
      assert_equal true, production
      assert path.end_with?('/.config/circle/turnstile.json')
    end
    RegistrationTurnstile.stub(:load_configuration, loader) do
      load File.join(ROOT, 'config/initializers/registration_turnstile.rb')
    end
    load File.join(ROOT, 'config/initializers/filter_parameter_logging.rb')
    filter = ActiveSupport::ParameterFilter.new(configuration.filter_parameters)
    filtered = filter.filter('cf-turnstile-response' => 'dummy-token', 'turnstile_secret_key' => DUMMY_SECRET)
    assert_equal '[FILTERED]', filtered['cf-turnstile-response']
    assert_equal '[FILTERED]', filtered['turnstile_secret_key']
  end

  def test_dummy_configuration_is_atomic_private_and_not_overwritten_by_invalid_input
    Dir.mktmpdir('circle-turnstile-test') do |dir|
      directory = File.join(dir, 'config')
      env = { 'TURNSTILE_SITE_KEY' => DUMMY_SITE, 'TURNSTILE_SECRET_KEY' => DUMMY_SECRET }
      TurnstileConfigurationWriter.write(directory: directory, environment: env)
      path = File.join(directory, 'turnstile.json')
      assert_equal 0700, File.stat(directory).mode & 0777
      assert_equal 0600, File.stat(path).mode & 0777
      assert_equal ['turnstile.json'], Dir.children(directory)
      RegistrationTurnstile.load_configuration(production: true, path: path)
      assert RegistrationTurnstile.configured?
      assert_equal DUMMY_SITE, RegistrationTurnstile.site_key
      assert_raises(TurnstileConfigurationWriter::InvalidConfiguration) do
        TurnstileConfigurationWriter.write(directory: directory, environment: env.merge('TURNSTILE_SECRET_KEY' => "bad\nvalue"))
      end
      RegistrationTurnstile.load_configuration(production: true, path: path)
      assert RegistrationTurnstile.configured?
      TurnstileConfigurationWriter.write(directory: directory, environment: env)
      assert_equal ['turnstile.json'], Dir.children(directory)
      link = File.join(dir, 'link')
      File.symlink(directory, link)
      assert_raises(TurnstileConfigurationWriter::InvalidConfiguration) do
        TurnstileConfigurationWriter.write(directory: link, environment: env)
      end
    end
  end

  def test_configuration_missing_malformed_and_local_defaults
    Dir.mktmpdir('circle-turnstile-test') do |dir|
      path = File.join(dir, 'dummy.json')
      [nil, '{', '[]'].each do |content|
        File.write(path, content) if content
        RegistrationTurnstile.load_configuration(production: true, path: path, environment: {})
        assert_equal :unavailable, RegistrationTurnstile.verify('dummy-token')
      end
      RegistrationTurnstile.load_configuration(production: false, path: path, environment: {})
      refute RegistrationTurnstile.required?
    end
  end

  def test_haml_shows_only_public_key_and_handles_missing_configuration
    source = File.read(File.join(ROOT, 'app/views/devise/shared/_registration_turnstile.html.haml'))
    template = Haml::Template.new { source }
    html = template.render
    assert_includes html, DUMMY_SITE
    assert_includes html, 'aria-live'
    refute_includes html, DUMMY_SECRET
    RegistrationTurnstile.configure(required: true)
    assert_includes template.render, '認証を準備中'
    RegistrationTurnstile.configure
    assert_empty template.render.strip
  end

  def test_all_three_registration_controllers_and_forms_are_wired
    %w[admin_users members exhibition_groups].each do |account|
      controller = File.read(File.join(ROOT, "app/controllers/#{account}/registrations_controller.rb"))
      assert_includes controller, 'include RegistrationTurnstileGuard'
      view = account == 'admin_users' ? 'devise' : account
      assert_includes File.read(File.join(ROOT, "app/views/#{view}/registrations/new.html.haml")), 'devise/shared/registration_bot_guard'
    end
    assert_includes File.read(File.join(ROOT, 'app/views/devise/shared/_registration_bot_guard.html.haml')), 'devise/shared/registration_turnstile'
  end

  def test_deploy_verifies_registration_on_both_new_hosts_without_inline_secrets
    workflow = YAML.load_file(File.join(ROOT, '.github/workflows/deploy_prod.yml'))
    jobs = workflow.fetch('jobs')
    assert_equal 'prepare', jobs.fetch('activate').fetch('needs')
    %w[prepare activate].each do |phase|
      job = jobs.fetch(phase)
      assert_equal %w[server4 server5], job.fetch('strategy').fetch('matrix').fetch('include').map { |host| host.fetch('server') }
      assert_equal 1, job.fetch('strategy').fetch('max-parallel')
      refute_includes job.to_s, 'secrets.TURNSTILE'
    end
    script = File.read(File.join(ROOT, 'ops/al2023/deploy.sh'))
    assert_includes script, 'CIRCLE_PUMA_SOCKET='
    assert_includes script, 'bundle exec ruby bin/verify_turnstile_readiness'
    refute_includes script, 'turnstile.json'
  end

  def test_readiness_requires_a_real_widget_inside_a_successful_form
    html = '<form><div class="registration-turnstile" data-sitekey="dummy-public-key"></div></form>'
    assert TurnstileFormReadiness.ready?(status: 200, body: html)
    refute TurnstileFormReadiness.ready?(status: 503, body: html)
    refute TurnstileFormReadiness.ready?(status: 200, body: '<p>認証を準備中</p>')
    refute TurnstileFormReadiness.ready?(status: 200, body: html.sub('dummy-public-key', ''))
    refute TurnstileFormReadiness.ready?(status: 200, body: html.sub('<form>', '').sub('</form>', ''))
  end
end
