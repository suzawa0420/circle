module PlaceImports
  class MizunoClient < OfficialClient
    private

    def approved_uri?(uri)
      return false unless uri.scheme == 'https' && uri.port == 443 && uri.userinfo.nil? && uri.fragment.nil?
      case uri.host
      when 'shisetsu.mizuno.jp'
        uri.query.nil? && (uri.path == '/robots.txt' || uri.path.match?(%r{\A/[a-zA-Z0-9_-]+(?:/(?:access|guide|gallery))?/?\z}))
      when 'sports-service.mizuno.jp'
        (uri.path == '/robots.txt' && uri.query.nil?) ||
          (uri.path == '/search/' && (uri.query.nil? || uri.query.match?(/\Apage=[1-9][0-9]{0,2}\z/)))
      else
        false
      end
    end
  end
end
