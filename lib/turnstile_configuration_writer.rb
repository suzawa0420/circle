# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'tempfile'

module TurnstileConfigurationWriter
  class InvalidConfiguration < StandardError; end

  def self.write(directory:, environment: ENV)
    values = { 'site_key' => environment['TURNSTILE_SITE_KEY'],
               'secret_key' => environment['TURNSTILE_SECRET_KEY'] }
    unless values.values.all? { |value| value.is_a?(String) && value.match?(/\A[A-Za-z0-9_-]{10,256}\z/) }
      raise InvalidConfiguration, 'Turnstile configuration is missing or invalid'
    end

    raise InvalidConfiguration, 'Unsafe configuration directory' if File.symlink?(directory)
    FileUtils.mkdir_p(directory, mode: 0700)
    raise InvalidConfiguration, 'Unsafe configuration owner' unless File.stat(directory).uid == Process.uid
    File.chmod(0700, directory)
    target = File.join(directory, 'turnstile.json')
    raise InvalidConfiguration, 'Unsafe configuration target' if File.symlink?(target)
    temporary = Tempfile.new('turnstile-', directory)
    begin
      temporary.chmod(0600)
      temporary.write(JSON.generate(values))
      temporary.flush
      temporary.fsync
      temporary.close
      File.rename(temporary.path, target)
    ensure
      temporary.close!
    end
    true
  end
end
