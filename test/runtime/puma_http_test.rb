# Real HTTP regression: Rack 3 returns multiple Set-Cookie values as an Array.
# Synthetic Rack app only; does not boot Rails or load production configuration.
require 'bundler/setup'
require 'minitest/autorun'
require 'puma'
require 'puma/configuration'
require 'net/http'
require 'stringio'

class PumaHttpTest < Minitest::Test
  def setup
    app = lambda do |env|
      status = env['PATH_INFO'] == '/redirect' ? 302 : 200
      headers = { 'content-type' => 'text/plain',
                  'set-cookie' => ['session=synthetic; Path=/; HttpOnly', 'remember=synthetic; Path=/; HttpOnly'] }
      headers['location'] = '/done' if status == 302
      [status, headers, ['synthetic response']]
    end
    @server = Puma::Server.new(app, nil, min_threads: 1, max_threads: 1, log_writer: Puma::LogWriter.new(StringIO.new, StringIO.new))
    @server.add_tcp_listener('127.0.0.1', 0)
    @port = @server.binder.ios.first.addr[1]
    @server.run
  end

  def teardown
    @server&.stop(true)
  end

  def test_multiple_cookies_survive_real_http_response
    response = request('/')
    assert_equal '200', response.code
    assert_equal 'synthetic response', response.body
    assert_equal ['session=synthetic; Path=/; HttpOnly', 'remember=synthetic; Path=/; HttpOnly'], response.get_fields('set-cookie')
  end

  def test_redirect_preserves_both_cookies
    response = request('/redirect')
    assert_equal '302', response.code
    assert_equal '/done', response['location']
    assert_equal 2, response.get_fields('set-cookie').size
  end

  def test_production_config_keeps_private_socket_and_single_threaded_workers
    config = Puma::Configuration.new(config_files: [File.expand_path('../../ops/al2023/puma.rb', __dir__)])
    config.load
    config.clamp
    options = config.options
    assert_equal 8, options[:workers]
    assert_equal 1, options[:min_threads]
    assert_equal 1, options[:max_threads]
    assert_equal true, options[:preload_app]
    assert_equal ["unix://#{File.expand_path('../..', __dir__)}/tmp/sockets/unicorn.sock?umask=0007"], options[:binds]
  end

  private

  def request(path)
    Net::HTTP.start('127.0.0.1', @port, nil, open_timeout: 5, read_timeout: 5) { |http| http.get(path) }
  end
end
