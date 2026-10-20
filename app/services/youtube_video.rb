require 'uri'

# Parse locally; never fetch a user-provided URL or embed arbitrary HTML.
class YoutubeVideo
  ID = /\A[A-Za-z0-9_-]{11}\z/
  HOSTS = %w[youtube.com www.youtube.com m.youtube.com music.youtube.com].freeze

  def self.id(url)
    uri = URI.parse(url.to_s.strip)
    return unless %w[http https].include?(uri.scheme) && uri.userinfo.nil?
    return unless uri.port == uri.default_port

    video_id = if %w[youtu.be www.youtu.be].include?(uri.host)
      uri.path.delete_prefix('/') if uri.path.count('/') == 1
    elsif HOSTS.include?(uri.host)
      if uri.path == '/watch'
        URI.decode_www_form(uri.query.to_s).to_h['v']
      elsif (match = uri.path.match(%r{\A/(?:shorts|embed|live)/([^/]+)/?\z}))
        match[1]
      end
    end
    video_id if video_id && ID.match?(video_id)
  rescue URI::InvalidURIError, ArgumentError
    nil
  end
end
