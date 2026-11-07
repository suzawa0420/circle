module PlaceImports
  # This operator host is linked by the foundation's facility directory.
  # No city directory, redirects, PDFs, forms or external links are fetched.
  class SendaiClient < OfficialClient
    HOST = 'ideka.spf-sendai.com'.freeze
    PATHS = %w[/robots.txt / /shisetsu/ /access/ /charge/ /yoyaku/].freeze

    private

    def approved_uri?(uri)
      uri.scheme == 'https' && uri.host == HOST && uri.port == 443 && uri.userinfo.nil? &&
        uri.query.nil? && uri.fragment.nil? && PATHS.include?(uri.path)
    end
  end
end
