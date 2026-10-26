module PlaceImports
  class MizunoSource
    KEY = 'mizuno_nationwide'.freeze
    HOST = 'shisetsu.mizuno.jp'.freeze
    ROOT = "https://#{HOST}".freeze
    DIRECTORY = 'https://sports-service.mizuno.jp/search/'.freeze
    class SourceError < StandardError; end

    def initialize(client: MizunoClient.new)
      @client = client
      @formatter = SetagayaDetails.new
      @robots = {}
    end

    def key
      KEY
    end

    def seeds
      JSON.parse(File.read(Rails.root.join('config/place_import_mizuno_seeds.json')))
    end

    # A maintenance page is not an empty nationwide directory. Callers retain
    # directory_complete=false, process the existing queue and retry discovery.
    def discover
      urls = []
      seen = []
      page = DIRECTORY
      complete = false
      100.times do
        raise SourceError, 'directory_pagination_loop' if seen.include?(page)
        seen << page
        doc = document(page)
        urls.concat(doc.css('a[href]').filter_map { |a| canonical_facility_url(a['href']) })
        next_page = doc.css('a[rel=next], .pagination a').filter_map do |a|
          u = URI.join(DIRECTORY, a['href'].to_s)
          u.to_s if u.host == 'sports-service.mizuno.jp' && u.path == '/search/' &&
            u.query.to_s.match?(/\Apage=[1-9][0-9]{0,2}\z/) && !seen.include?(u.to_s)
        end.first
        unless next_page
          complete = true
          break
        end
        page = next_page
      end
      raise SourceError, 'directory_page_limit' unless complete
      raise SourceError, 'empty_or_changed_directory' if urls.empty?
      urls.uniq.sort.map { |url| { 'url' => url } }
    end

    def fetch(url)
      canonical = canonical_facility_url(url)
      raise SourceError, 'unapproved_facility_url' unless canonical == url
      home, access, guide, gallery = [url, "#{url}/access", "#{url}/guide", "#{url}/gallery"].map { |u| document(u) }
      info = access.at_css('main .facility_info_section .info_wrap')
      raise SourceError, 'missing_facility_metadata' unless info
      name = text(info.at_css('.name')).gsub(/\A[[:space:]]+|[[:space:]]+\z/, '')
      address = text(info.at_css('.address')).gsub(/\s+/, '')
      prefecture = address[/\A(?:北海道|東京都|京都府|大阪府|.{2,3}県)/]
      summary = guide.css('#facility_use_tbl tr').to_h do |row|
        [text(row.at_css('th')), text(row.at_css('td'))]
      end
      # Classify only an unambiguous facility name. Multi-site operation pages
      # need human review rather than assigning outdoor courts an indoor tag.
      tag = if name.match?(/体育館|アリーナ/) && !name.match?(/｜|／|体育館等|体育館.*[・、].*(?:グラウンド|運動|公園)/)
        '1'
      elsif name.match?(/テニス|フットサル|スポーツガーデン/) && !name.match?(/屋内|インドア/)
        '2'
      end
      modal_nodes = gallery.css('.inline-wrap')
      modal_titles = modal_nodes.map { |modal| text(modal.at_css('.top_header')) }
      if tag.nil? && name.match?(/センター|プラザ|交流館|スポーツ館/) && !name.match?(/｜|／|体育館等/)
        indoor = modal_titles.any? { |title| title.match?(/アリーナ|体育館|体育室|フロア/) }
        outdoor = modal_titles.any? { |title| title.match?(/屋外|テニスコート|フットサル場|グラウンド|陸上|野球/) }
        tag = '1' if indoor && !outdoor
      end
      # An outdoor venue name does not make its covered/indoor courts outdoor.
      tag = nil if tag == '2' && modal_nodes.any? { |node| text(node).match?(/インドア|屋内|屋根あり/) }
      spaces = modal_nodes.filter_map do |modal|
        title = text(modal.at_css('.top_header'))
        matches = tag == '1' ? title.match?(/アリーナ|体育館|体育室|フロア/) : title.match?(/テニス|フットサル|コート/)
        next unless matches && !title.match?(/観客席|観覧席|役員室|来賓室|本部|レストラン|トレーニング|会議|更衣/)
        text(modal.at_css('.txt_wrap'))
      end
      scale = spaces.uniq.join("\n\n")
      sports = SetagayaSource::SPORT_WORDS.select do |sport|
        pattern = case sport
        when 'バスケットボール' then /バスケット(?:ボール)?/
        when 'バレーボール' then /バレー(?:ボール)?/
        else Regexp.new(Regexp.escape(sport))
        end
        spaces.any? do |space|
          value = space.unicode_normalize(:nfkc)
          value = value.gsub('硬式・ソフトテニス', '硬式テニス').gsub('ソフトテニス', '') if sport == 'テニス'
          value.match?(pattern) && !value.match?(/#{pattern.source}[^。\n]{0,24}(?:不可|できません|禁止)/)
        end
      end
      access_body = access.at_css('.show_body_access')
      parking_sections = access_body ? access_body.css('h3,h4').select do |heading|
        text(heading).match?(/駐車/) || (text(heading).match?(/車で/) && section(heading).include?('駐車'))
      end : []
      parking = parking_sections.map { |h| section(h) }.reject(&:blank?).join("\n\n")
      if parking.blank? && access_body
        parking = text(access_body)[/[^\n]*駐車[^\n]*(?:\n[^\n]+){0,3}/].to_s
      end
      transport_sections = access_body ? access_body.css('h3,h4').select { |h| text(h).match?(/電車|バス|徒歩|自転車/) } : []
      transport = transport_sections.filter_map do |heading|
        route = section(heading)
        # A heading and decorative bullets are not a confirmed access route.
        "#{text(heading)}\n#{route}" if route.match?(/[[:alnum:]]/)
      end.join("\n\n")
      transport = text(access_body) if transport_sections.empty? && access_body
      alerts = home.css('a[href]').select do |a|
        a['href'].include?("#{URI(url).path}/news/") && text(a).match?(/閉館|閉鎖|長期休館|臨時休館|営業休止|利用停止/)
      end.map { |a| text(a).first(250) }.uniq
      meta_note = text(info.at_css('.holiday'))
      time = summary.find { |label, _| label.match?(/営業時間|開館時間|体育館利用時間/) }&.last
      time ||= meta_note[/(?:開館時間|営業時間)\s*[:：]?\s*(.+?)(?=休館日|休場日|定休日|$)/, 1]&.strip
      holiday = summary.find { |label, _| label.match?(/休館|休場|定休日|休業日/) }&.last
      holiday ||= meta_note[/(?:休館日|休場日|定休日)\s*[:：]?\s*(.+)\z/, 1]&.strip
      price = prices(guide)
      if price.present?
        conditions = summary.select { |label, _| label.match?(/対象|資格|利用条件/) }.map { |label, value| "#{label}：#{value}" }.join("\n")
        price = [price, conditions.presence, "公式料金：#{url}/guide\n確認日：#{Date.current.iso8601}"].compact.join("\n\n")
      end
      {
        'name' => name, 'address' => address, 'prefecture' => prefecture, 'city' => nil,
        'tag' => tag, 'sports' => sports, 'tel' => text(info.at_css('.tel a')),
        'url' => url, 'access' => transport.presence, 'parking' => parking.presence,
        'time' => time.presence, 'regular_holiday' => holiday.presence,
        'scale' => scale.presence, 'price' => price.presence, 'alerts' => alerts,
        'evidence' => [{ 'url' => "#{url}/gallery", 'label' => '公式施設案内', 'text' => scale.first(4000) }]
      }
    end

    private

    def canonical_facility_url(value)
      uri = URI.parse(value.to_s)
      return unless uri.scheme == 'https' && uri.host == HOST && uri.port == 443 && uri.userinfo.nil? && uri.query.nil? &&
        uri.path.match?(%r{\A/(?:m-|mss-|[0-9])[a-zA-Z0-9_-]+/?\z}) && uri.path != '/mizuno'
      "#{ROOT}#{uri.path.delete_suffix('/')}"
    rescue URI::InvalidURIError
      nil
    end

    def document(url)
      uri = URI(url)
      unless @robots.key?(uri.host)
        body = @client.get("https://#{uri.host}/robots.txt")
        @robots[uri.host] = body.lines.filter_map do |line|
          value = line.sub(/#.*/, '').match(/^\s*Disallow:\s*(\S+)/i)&.[](1)
          Regexp.new('\\A' + Regexp.escape(value).gsub('\\*', '.*').sub(/\\\$\z/, '\\z')) if value.present?
        end
      end
      raise SourceError, 'robots_disallowed' if @robots.fetch(uri.host).any? { |rule| rule.match?(uri.path) }
      Nokogiri::HTML(@client.get(url))
    end

    def text(node)
      @formatter.send(:text, node)
    end

    def section(heading)
      @formatter.send(:section_text, heading)
    end

    def prices(guide)
      body = guide.at_css('.show_body_guide')
      return '' unless body
      sections = body.css('h2,h3,h4').filter_map do |heading|
        title = text(heading)
        next unless title.match?(/利用料金|使用料金|使用料|専用利用|個人利用|専用使用|個人使用/)
        next if title.match?(/プール|トレーニング|研修|講習|教室/)
        value = section(heading)
        next unless value.match?(/[0-9][0-9,，]*\s*円/)
        [title, value].join("\n")
      end
      return sections.uniq.join("\n\n") if sections.any?
      # Fall back only to explicitly labelled court tariffs, never a training
      # course table whose fine print happens to mention a gymnasium.
      body.css('table').filter_map do |table|
        matrix = @formatter.send(:table_text, table)
        next unless matrix.match?(/[0-9][0-9,，]*\s*円/)
        heading = text(table.xpath('preceding::*[self::h3 or self::h4][1]').first)
        next if heading.match?(/プール|トレーニング|研修|講習|教室/)
        labels = table.css('tr').map { |row| text(row.element_children.first) }.join(' ')
        caption_node = table.previous_sibling
        caption_node = caption_node.previous_sibling while caption_node && text(caption_node).blank?
        caption = text(caption_node)
        next unless (heading + caption + labels).match?(/アリーナ|体育館|体育室|フロア|コート|テニス|フットサル|卓球/)
        [heading, caption, matrix].reject(&:blank?).uniq.join("\n")
      end.join("\n\n")
    end
  end
end
