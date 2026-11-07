require 'uri'

module PlaceImports
  # Deliberately limited to one reviewed operator layout, not all of Sendai.
  class SendaiSource
    KEY = 'sendai_sports'.freeze
    # Reviewed 2026-11-07: foundation detail link /ideka/ redirects to this
    # operator host. Discovery must separately review each additional host.
    PROVENANCE = 'https://www.spf-sendai.jp/sisetsu/gym/ideka-gym/'.freeze
    ROOT = 'https://ideka.spf-sendai.com'.freeze
    URL = "#{ROOT}/".freeze
    class SourceError < StandardError; end

    def initialize(client: SendaiClient.new)
      @client = client
    end

    def key; KEY; end
    def seeds; [{ 'url' => URL }]; end

    def discover
      # Returning the seed here would falsely mark city discovery complete.
      raise SourceError, 'partial_reviewed_seed_only'
    end

    def fetch(url)
      raise SourceError, 'unapproved_facility_url' unless url == URL
      pages = %w[/ /shisetsu/ /access/ /charge/ /yoyaku/].to_h { |path| [path, document(path)] }
      home = pages.fetch('/')
      facility = content(pages.fetch('/shisetsu/'))
      access = content(pages.fetch('/access/'))
      charge = content(pages.fetch('/charge/'))
      booking = content(pages.fetch('/yoyaku/'))
      name = clean(home.at_css('h1'))
      raise SourceError, 'missing_facility_metadata' unless name == '出花体育館'
      info = details(facility.at_css('.kihon'))
      location = details(access.at_css('.kihon'))
      address = location['所在地'].to_s.lines.find { |line| line.start_with?('宮城県仙台市') }
      raise SourceError, 'missing_facility_metadata' unless address
      court = details(facility.at_css('#gaiyo01'))
      sports_text = court['利用可能種目'].to_s
      available = available_sports(home)
      sports = SetagayaSource::SPORT_WORDS.select do |sport|
        next false unless available.include?(sport)
        sports_text.unicode_normalize(:nfkc).lines.any? do |line|
          line.strip.match?(/\A#{Regexp.escape(sport)}(?:コート)?\s*\d+\s*[面台](?:\s|[（(※]|\z)/)
        end
      end
      scale_sports = sports_text.lines.map do |line|
        if line.unicode_normalize(:nfkc).strip.match?(/\Aテニス(?:コート)?\s*\d+\s*面/) && !sports.include?('テニス')
          listed = available_sports_text(home)
          "施設表記：#{line.strip}。公式の利用可能な種目：#{listed.join('、')}。硬式テニスの利用可否は未確認。"
        else
          line.strip
        end
      end.join("\n")
      route_heading = access.css('h4').find { |h| clean(h) == '公共交通機関' }
      route = route_heading&.next_element
      routes = clean(route) if route&.name == 'ul'
      fee = render(charge) if charge.css('table td').any? { |td| clean(td).match?(/\d[\d,]*円/) }
      if fee.present?
        required = %w[競技場（全面） 競技場（区分） アマチュアスポーツ 入場料なし 入場料徴収 非営利 営利 土曜・日曜・祝日 2割増 個人使用 使用料／回]
        raise SourceError, 'unverified_rate_qualifications' unless required.all? { |label| fee.include?(label) }
      end
      # Keep scope, availability and concession qualifications alongside rates.
      personal_heading = booking.at_css('h3#ank02')
      personal = personal_heading&.next_element
      personal_text = clean(personal)
      concession = court['使用料'].to_s
      unless clean(personal_heading) == '個人使用について' && personal&.name == 'p' &&
          %w[予約 利用可能日 個人使用料 高校生以上 小中学生].all? { |label| personal_text.include?(label) } &&
          %w[個人使用 障がい者手帳 窓口 提示 無料].all? { |label| concession.include?(label) }
        raise SourceError, 'unverified_booking_qualifications'
      end
      qualifications = [personal_text, concession].join("\n")
      price = [fee, qualifications, "公式料金：#{ROOT}/charge/", "確認日：#{Date.current.iso8601}"].join("\n\n") if fee.present?
      alerts = closure_alerts(home)
      {
        'name' => name, 'address' => address.strip, 'prefecture' => '宮城県', 'city' => nil,
        'tag' => '1', 'sports' => sports, 'url' => URL,
        'tel' => location['所在地'].to_s[/TEL\s*(0\d{1,4}-\d{1,4}-\d{3,4})/, 1],
        'access' => routes.presence, 'parking' => info['駐車場'].presence,
        'time' => location['開館時間'].presence, 'regular_holiday' => location['休館日'].presence,
        'scale' => [court['面積・仕様'], scale_sports].reject(&:blank?).join("\n").presence,
        'price' => price, 'alerts' => alerts,
        'evidence' => pages.map { |path, doc| { 'url' => "#{ROOT}#{path}", 'text' => (path == '/' ? [clean(doc.at_css('#newsINDEX')), clean(doc.at_css('#aboutINDEX'))].join("\n") : clean(doc.at_css('#rightCo'))) } }
      }
    end

    private

    def available_sports_text(home)
      list = home.css('#aboutINDEX .komoku dl').find { |node| clean(node.at_css('dt')) == '利用可能な種目' }
      raise SourceError, 'unverified_available_sports' unless list
      list.css('dd').map { |node| clean(node).unicode_normalize(:nfkc).strip }
        .reject { |text| text.include?('お問い合わせ') || text.blank? }
    end

    def available_sports(home)
      available_sports_text(home).filter_map do |label|
        # The reviewed operator spells badminton バトミントン on its homepage.
        next 'バドミントン' if label == 'バトミントン'
        next 'テニス' if label == '硬式テニス'
        label if label != 'テニス' && SetagayaSource::SPORT_WORDS.include?(label)
      end
    end

    def closure_alerts(home)
      news = home.css('#newsINDEX')
      unless news.one? && clean(news.first.at_css('h2')).include?('お知らせ') && news.first.css('dl dd').any?
        raise SourceError, 'unverified_notice_structure'
      end
      # Include unlinked emergency notices and table/div text, not only links.
      # Remove known navigation and routine closure-calendar sidebars first.
      body = home.at_css('body')&.dup
      raise SourceError, 'unverified_notice_structure' unless body
      body.css('script,style,header,footer,nav,#leftCo,#navFIX,#navF,.boxKyukan').remove
      blocks = body.css('a,p,div,td,th,dd,li,h2,h3,h4').select do |node|
        clean(node).match?(/閉館|閉鎖|休館|休止|停止|利用制限|利用不可|工事|改修/)
      end
      # Prefer the smallest complete block, avoiding duplicate whole-page alerts.
      blocks.reject { |node| blocks.any? { |other| other != node && other.ancestors.include?(node) } }
        .map { |node| clean(node) }.uniq
    end

    def document(path)
      @disallowed ||= @client.get("#{ROOT}/robots.txt").lines.filter_map do |line|
        rule = line.sub(/#.*/, '').match(/^\s*Disallow:\s*(\S+)/i)&.[](1)
        Regexp.new('\\A' + Regexp.escape(rule).gsub('\\*', '.*').sub(/\\\$\z/, '\\z')) if rule.present?
      end
      raise SourceError, 'robots_disallowed' if @disallowed.any? { |rule| rule.match?(path) }
      Nokogiri::HTML(@client.get("#{ROOT}#{path}"))
    end

    def content(doc)
      doc.at_css('#rightCo') || raise(SourceError, 'missing_facility_content')
    end

    def details(node)
      return {} unless node
      node.css('tr').to_h { |row| [clean(row.at_css('th')), clean(row.at_css('td'))] }
    end

    def clean(node)
      return '' unless node
      copy = node.dup
      copy.css('script,style,nav,form').remove
      copy.css('br').each { |br| br.replace("\n") }
      copy.css('p,li,h3,h4,h5').each { |n| n.add_next_sibling(Nokogiri::XML::Text.new("\n", copy.document)) }
      copy.text.gsub(/[\t\r\f\v\u00a0 ]+/, ' ').lines.map(&:strip).reject(&:empty?).join("\n")
    end

    # Expand spanning cells so every tariff row retains its admission/use class.
    def render(node)
      copy = node.dup
      copy.css('table').each do |table|
        grid = []
        table.xpath('./tr | ./thead/tr | ./tbody/tr | ./tfoot/tr').each_with_index do |row, y|
          grid[y] ||= []
          x = 0
          row.element_children.select { |cell| %w[th td].include?(cell.name) }.each do |cell|
            x += 1 while grid[y][x]
            width, height = [cell['colspan'].to_i, 1].max, [cell['rowspan'].to_i, 1].max
            raise SourceError, 'unsupported_rate_table' if width > 20 || height > 100
            height.times do |dy|
              grid[y + dy] ||= []
              width.times { |dx| grid[y + dy][x + dx] = clean(cell).gsub(/\s+/, ' ') }
            end
            x += width
          end
        end
        table.replace(Nokogiri::XML::Text.new("\n#{grid.map { |r| r.join(' | ') }.join("\n")}\n", copy.document))
      end
      clean(copy)
    end
  end
end
