require 'minitest/autorun'
require 'open3'

class UnicornReadinessTest < Minitest::Test
  SCRIPT = File.expand_path('../../bin/restart_unicorn_safely', __dir__)
  # All process/network/wait commands are replaced with shell functions. These
  # tests never signal a real PID, sleep, or make an HTTP request.
  MOCKS = <<~BASH
    restarted=0
    cat() { if [ "$restarted" = 0 ]; then echo 100; else echo 200; fi; }
    kill() {
      if [ "$1" = '-USR2' ]; then restarted=1; return 0; fi
      if [ "$2" = 100 ] && [ "$restarted" = 1 ]; then return 1; fi
      return 0
    }
    curl() { echo probe >&2; printf 200; }
    sleep() { SECONDS=$((SECONDS + 30)); }
  BASH

  def run_script(overrides = '')
    Open3.capture3('bash', '-c', "#{MOCKS}\n#{overrides}\nsource \"$1\"", 'test', SCRIPT)
  end

  def test_requires_three_real_app_successes_after_master_replacement
    out, err, status = run_script
    assert status.success?
    assert_equal 3, err.lines.count { |line| line.strip == 'probe' }
    assert_includes out, 'readiness verified'
  end

  def test_does_not_continue_on_http_failure
    out, _, status = run_script('curl() { printf 502; }')
    refute status.success?
    assert_includes out, 'deployment stopped'
  end

  def test_does_not_accept_unchanged_master_even_when_http_would_work
    out, err, status = run_script('cat() { echo 100; }')
    refute status.success?
    refute_includes err, 'probe'
    assert_includes out, 'deployment stopped'
  end

  def test_rejects_invalid_pid_without_signaling
    out, err, status = run_script('cat() { echo 0; }; kill() { echo unsafe >&2; return 1; }')
    refute status.success?
    refute_includes err, 'unsafe'
    assert_includes out, 'Invalid Unicorn PID'
  end
end
