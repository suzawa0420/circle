module PlaceImports
  class SapporoClient < OfficialClient
    HOST = 'www.city.sapporo.jp'.freeze
    GYMS = %w[higashi kita atsubetsu toyohira shiroishi minami teine kiyota nishi nakajima].freeze
    BASE = '/sports/sisetsu/institution/'.freeze
    PATHS = (GYMS.map { |slug| "#{BASE}gym/#{slug}.html" } +
      ['/robots.txt', "#{BASE}index.html", "#{BASE}ryokin/kojin.html", '/higashi/shisetu/shisetu_2.html',
       "#{BASE}tennis/hiragishi.html", "#{BASE}ryokin/senyo-outdoor.html"]).freeze

    private

    def approved_uri?(uri)
      uri.scheme == 'https' && uri.host == HOST && uri.port == 443 && uri.userinfo.nil? &&
        uri.query.nil? && uri.fragment.nil? && (PATHS.include?(uri.path) || uri.path.match?(%r{\A/sports/sisetsu/institution/(?:gym|tennis)/[a-z][a-z0-9_-]*\.html\z}))
    end
  end
end
