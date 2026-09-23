# frozen_string_literal: true

require 'digest'

module AbuseProtection
  ACCOUNTS = %w[admin_users members exhibition_groups].freeze

  def self.endpoint(request)
    path = Rack::Utils.unescape_path(request.path).sub(/\.[a-z0-9]+\z/i, '').sub(%r{/\z}, '')
    return unless request.post?

    return :signup if ACCOUNTS.any? { |account| path == "/#{account}" }
    return :login if ACCOUNTS.any? { |account| path == "/#{account}/sign_in" }
    return :password if ACCOUNTS.any? { |account| path == "/#{account}/password" }
  end

  def self.configure(store:, logger:)
    Rack::Attack.cache.store = store
    # Rack::Attack is inserted automatically by its Railtie, after RemoteIp.
    # Use Rails' trusted-proxy handling, never the first raw X-Forwarded-For.
    { signup: [10, 3600], login: [60, 300], password: [10, 3600] }.each do |kind, (limit, period)|
      Rack::Attack.throttle("account/#{kind}", limit: limit, period: period) do |request|
        if endpoint(request) == kind
          Digest::SHA256.hexdigest(ActionDispatch::Request.new(request.env).remote_ip.to_s)
        end
      end
    end

    Rack::Attack.throttled_responder = lambda do |request|
      period = request.env.fetch('rack.attack.match_data').fetch(:period)
      retry_after = period - (Time.now.to_i % period)
      logger.error("[AbuseProtection] throttled rule=#{request.env['rack.attack.matched']}")
      [429, { 'Content-Type' => 'text/plain; charset=utf-8',
              'Cache-Control' => 'no-store', 'Retry-After' => retry_after.to_s },
       ['短時間に操作が集中しています。しばらく待ってから再度お試しください。']]
    end
  end
end
