module PlaceImports
  # One reviewed operator venue. Unknown news, redirects, PDFs and images are not fetched.
  class MiyazakiClient < OfficialClient
    HOST = 'ikimenomori.jp'.freeze
    REVIEW = JSON.parse(File.read(Rails.root.join('config/place_import_miyazaki_review.json'))).freeze
    PATHS = (['/robots.txt'] + REVIEW.map { |item| item.fetch('path') }).freeze

    private

    def approved_uri?(uri)
      uri.scheme == 'https' && uri.host == HOST && uri.port == 443 && uri.userinfo.nil? &&
        uri.query.nil? && uri.fragment.nil? && PATHS.include?(uri.path)
    end
  end
end
