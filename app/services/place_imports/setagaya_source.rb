module PlaceImports
  class SetagayaSource
    KEY = 'setagaya_sports'.freeze
    ROOT = 'https://www.se-sports.or.jp'.freeze
    LIMIT = 24
    SPORT_WORDS = %w[バスケットボール バレーボール バドミントン フットサル テニス 卓球].freeze
    class SourceError < StandardError; end

    def initialize(client: OfficialClient.new)
      @client = client
    end

    def key
      KEY
    end

    def collect
      @disallowed = robots_disallowed_paths(@client.get("#{ROOT}/robots.txt"))
      listing = document('/facility/')
      paths = listing.css('a[href]').filter_map { |a| safe_path(a['href'], 'facility') }.uniq.reject { |p| p == '/facility/' }
      raise SourceError, 'empty_directory' if paths.empty?
      paths.first(LIMIT).filter_map { |path| extract(path) }
    end

    private

    # Conservatively honor all agents' Disallow rules, including wildcard paths.
    def robots_disallowed_paths(text)
      text.lines.filter_map do |line|
        value = line.sub(/#.*/, '').match(/^\s*Disallow:\s*(\S+)/i)&.[](1)
        next if value.blank?
        Regexp.new('\\A' + Regexp.escape(value).gsub('\\*', '.*').sub(/\\\$\z/, '\\z'))
      end
    end

    def document(path)
      raise SourceError, 'robots_disallowed' if @disallowed.any? { |rule| rule.match?(path) }
      Nokogiri::HTML(@client.get("#{ROOT}#{path}"))
    end

    def safe_path(href, section)
      uri = URI.join(ROOT, href)
      return unless uri.scheme == 'https' && uri.host == OfficialClient::HOST && uri.port == 443 && uri.userinfo.nil? && uri.query.nil?
      uri.path if uri.path.match?(%r{\A/#{section}/[a-z0-9-]+/\z})
    rescue URI::InvalidURIError
      nil
    end

    def extract(path)
      doc = document(path)
      name = doc.at_css('.c-mv__title')&.text&.strip
      details = doc.css('.c-summaryTable__item').to_h do |row|
        [row.at_css('dt')&.text&.strip, row.at_css('dd')&.text&.gsub(/\s+/, ' ')&.strip]
      end
      return if name.blank?
      # A pool page can introduce an adjacent school court. Do not publish that
      # court under the pool's name or contact details.
      return if name.match?(/プール|トレーニングルーム/)
      # Restrict evidence to facility introduction pages, never shared navigation.
      links = doc.css('.p-facility-singleTab__facilityinfoLink[href]').filter_map do |a|
        p = safe_path(a['href'], 'facilityinfo')
        [p, a.text.strip] if p && a.text.match?(/体育館|テニス|球技場|運動場/)
      end.uniq.first(8)
      return if links.empty?
      facilities = []
      evidence = links.map do |p, label|
        detail = document(p)
        facilities << { document: detail, label: label.gsub(/\s+/, ' '), url: "#{ROOT}#{p}" }
        content = detail.at_css('main')&.dup
        raise SourceError, 'missing_detail_content' unless content
        content.css('script, style, nav, .p-search, .c-search, .l-footer, form').remove
        text = SetagayaDetails.new.basic_information(content)
        { 'url' => "#{ROOT}#{p}", 'label' => label, 'text' => text.first(4000) }
      end
      sports = SPORT_WORDS.select do |sport|
        evidence.any? do |item|
          text = item['text'].unicode_normalize(:nfkc)
          if sport == 'テニス'
            text = text.gsub('ソフトテニス', '')
          end
          text.match?(/#{Regexp.escape(sport)}\s*[:：]?\s*\d+\s*(面|台)/) ||
            (sport == 'テニス' && item['label'].include?('テニス') && !item['label'].include?('ソフト') && text.match?(/\d+\s*面/))
        end
      end
      title_text = links.map(&:last).join(' ')
      indoor = title_text.match?(/体育館/)
      outdoor = title_text.match?(/テニス|球技場|運動場/)
      alerts = doc.css('.c-news__itemTitle').map(&:text).select { |t| t.match?(/閉鎖|閉館|休館|利用停止|利用休止|廃止|改修/) }.map { |t| t.strip.first(200) }
      address = details['住所'].to_s.sub(/〒\s*\d{3}-?\d{4}\s*/, '').strip
      {
        'name' => name, 'address' => address, 'prefecture' => '東京都', 'city' => '世田谷区',
        'tag' => indoor && !outdoor ? '1' : (outdoor && !indoor ? '2' : nil),
        'sports' => sports, 'tel' => details['電話番号'].to_s[/0\d{1,4}-\d{1,4}-\d{3,4}/],
        'url' => "#{ROOT}#{path}", 'evidence' => evidence, 'alerts' => alerts
      }.merge(SetagayaDetails.new.call(doc, facilities))
    end
  end
end
