# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'

# Bounded, host-local counters shared by all Unicorn workers (no new service).
# Keys are hashed; no addresses, passwords or request bodies are persisted.
class AbuseCounterStore
  SHARDS = 64
  MAX_ENTRIES = 2048

  def initialize(directory, logger: nil)
    @directory = directory.to_s
    @logger = logger
  end

  def increment(key, amount, expires_in:)
    digest = Digest::SHA256.hexdigest(key)
    FileUtils.mkdir_p(@directory, mode: 0700)
    path = File.join(@directory, "#{digest.to_i(16) % SHARDS}.json")
    File.open(path, File::RDWR | File::CREAT, 0600) do |file|
      file.flock(File::LOCK_EX)
      now = Time.now.to_f
      raw = file.read
      entries = begin
        raw.empty? ? {} : JSON.parse(raw)
      rescue JSON::ParserError
        @logger&.error('[AbuseProtection] recovering interrupted counter write')
        {}
      end
      entries.delete_if { |_id, entry| entry[1] <= now }
      # Never evict active counters to admit a new attacker-controlled key.
      if !entries.key?(digest) && entries.size >= MAX_ENTRIES
        @logger&.error('[AbuseProtection] counter capacity reached')
        return 1
      end
      count, expiry = entries.fetch(digest, [0, now + expires_in])
      entries[digest] = [count + amount, expiry]
      file.rewind
      file.write(JSON.generate(entries))
      file.truncate(file.pos)
      count + amount
    end
  rescue SystemCallError, IOError, JSON::ParserError
    # A disk problem must not take down registration/login. Do not log keys.
    @logger&.error('[AbuseProtection] counter storage unavailable')
    1
  end
end
