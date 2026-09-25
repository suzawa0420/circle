# Use the shared counter store and responder configured in rack_attack.rb.
class Rack::Attack
  posting_path = %r{\A/(?:users/\d+/reviews|coat/places/\d+/place_reviews|circles/\d+/blogs)(?:/\d+)?(?:\.[^/]+)?/?\z}i
  normalized_path = ->(req) { Rack::Utils.unescape_path(req.path).squeeze('/') }
  client_ip = lambda do |req|
    # Use the same proxy-aware identity as the controller, not an arbitrary
    # CF-IPCountry / CF-Connecting-IP supplied by the visitor.
    ActionDispatch::Request.new(req.env).remote_ip
  end

  throttle('posts/ip/minute', limit: 5, period: 1.minute) do |req|
    client_ip.call(req) if %w[POST PUT PATCH].include?(req.request_method) && posting_path.match?(normalized_path.call(req))
  end

  throttle('posts/ip/hour', limit: 30, period: 1.hour) do |req|
    client_ip.call(req) if %w[POST PUT PATCH].include?(req.request_method) && posting_path.match?(normalized_path.call(req))
  end

end
