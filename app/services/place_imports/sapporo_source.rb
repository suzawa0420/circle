require 'uri'

module PlaceImports
  # Reviewed municipal gym pages only. Operator links and PDFs are never fetched.
  class SapporoSource
    KEY = 'sapporo_sports'.freeze
    ROOT = 'https://www.city.sapporo.jp'.freeze
    DIRECTORY = "#{ROOT}/sports/sisetsu/institution/index.html".freeze
    FEES = "#{ROOT}/sports/sisetsu/institution/ryokin/kojin.html".freeze
    EAST_HOURS = "#{ROOT}/higashi/shisetu/shisetu_2.html".freeze
    TENNIS = "#{ROOT}/sports/sisetsu/institution/tennis/hiragishi.html".freeze
    OUTDOOR_FEES = "#{ROOT}/sports/sisetsu/institution/ryokin/senyo-outdoor.html".freeze
    SPORTS = %w[バスケットボール バレーボール バドミントン テニス 卓球].freeze
    class SourceError < StandardError; end

    def initialize(client: SapporoClient.new)
      @client = client
    end

    def key
      KEY
    end

    def seeds
      [{ 'url' => TENNIS }, { 'url' => "#{ROOT}#{SapporoClient::BASE}gym/nakajima.html" }]
    end

    def discover
      # Completeness refers only to gym/tennis links on this single municipal
      # listing, not all sports facilities or all facilities in Sapporo.
      content = document(DIRECTORY)
      unless clean(content.at_css('h1')) == 'スポーツ施設' && content.css('h2,h3').any? { |node| clean(node) == '施設一覧' }
        raise SourceError, 'empty_or_changed_directory'
      end
      if content.css('a[href]').any? { |node| node['rel'].to_s.split.include?('next') || clean(node).match?(/次のページ|次へ/) }
        raise SourceError, 'directory_scope_unverified'
      end
      targets = content.css('a[href]').filter_map do |node|
        url = URI.join(DIRECTORY, node['href']).to_s
        { 'url' => url, 'name' => clean(node) } if facility_url?(url)
      rescue URI::Error
        nil
      end.uniq { |item| item['url'] }
      raise SourceError, 'empty_or_changed_directory' if targets.empty?
      raise SourceError, 'directory_page_limit' if targets.size > 50
      targets

    end

    def fetch(url)
      raise SourceError, 'unapproved_facility_url' unless facility_url?(url)
      content = document(url)
      name = clean(content.at_css('h1'))
      details = table_details(content)
      address = details['住所'].to_s
      unless name.present? && address.start_with?('札幌市')
        raise SourceError, 'missing_facility_metadata'
      end
      return tennis_data(content, name, details, url) if url == TENNIS
      # New municipal court URLs are queued for review, not forced into a gym parser.
      raise SourceError, 'missing_facility_metadata' if URI.parse(url).path.include?('/tennis/')
      equipment = content.css('table').find { |table| table.css('th').any? { |th| clean(th) == '種目' } }
      sport_rows = equipment ? equipment.css('tr').select do |row|
        SPORTS.include?(clean(row.at_css('td'))) && clean(row).match?(/\d+\s*[面台]/)
      end : []
      sports = sport_rows.map { |row| clean(row.at_css('td')) }
      fees = SapporoClient::GYMS.any? { |slug| url.end_with?("/gym/#{slug}.html") } ? fee_text : nil
      hours = details['利用時間']
      evidence = [{ 'url' => url, 'text' => clean(content) }]
      if url.end_with?('/higashi.html')
        ward = document(EAST_HOURS)
        # Do not import the older ward page's superseded prices.
        if clean(ward.at_css('h1')) == name && table_details(ward)['電話'] == details['電話']
          hours = table_details(ward)['利用時間']
          evidence << { 'url' => EAST_HOURS, 'text' => "#{name} 利用時間 #{hours}" }
        end
      end
      evidence << { 'url' => FEES, 'text' => fees } if fees.present?
      alerts = closure_alerts(content)
      {
        'name' => name, 'address' => "北海道#{address}", 'prefecture' => '北海道',
        'city' => '札幌市', 'url' => url,
        'tag' => name.match?(/体育館|体育センター/) ? '1' : nil,
        'tel' => details['電話'], 'sports' => sports,
        'access' => section_text(content, '交通アクセス'), 'parking' => details['駐車場'],
        'time' => hours, 'regular_holiday' => details['休館日'],
        'scale' => equipment && table_text(equipment), 'price' => fees,
        'alerts' => alerts, 'evidence' => evidence
      }
    end

    private

    def closure_alerts(content)
      pattern = /閉鎖|閉館|利用停止|利用休止|廃止|改修|工事|臨時休館|臨時休場/
      alerts = content.css('h2,h3,h4,p,li,a,td,th,div').select do |node|
        node.name != 'div' || node.element_children.empty?
      end.map { |node| clean(node) }.select { |text| text.match?(pattern) }.uniq
      # Unknown markup must not hide a closure from the registration gate.
      text = clean(content)
      alerts << text if alerts.empty? && text.match?(pattern)
      alerts
    end

    def facility_url?(url)
      uri = URI.parse(url)
      uri.scheme == 'https' && uri.host == SapporoClient::HOST && uri.port == 443 &&
        uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? &&
        uri.path.match?(%r{\A/sports/sisetsu/institution/(?:gym|tennis)/[a-z][a-z0-9_-]*\.html\z})
    rescue URI::Error
      false
    end

    def tennis_data(content, name, details, url)
      rates = document(OUTDOOR_FEES)
      label = rates.css('li').find { |node| clean(node) == '平岸庭球場（硬式）' }
      table = label&.parent&.next_element
      price = nil
      if table&.name == 'table' && clean(table).include?('高校生以下') && clean(table).include?('1時間') && clean(table).match?(/\d,\d{3}/)
        heading = rates.css('h2').find { |node| clean(node) == '利用料金表' }
        conditions = heading ? heading.xpath('following-sibling::*').take_while { |node| node.name != 'h3' }.map do |node|
          # This surcharge explicitly applies only to Tsukisamu archery.
          applicable = node.dup
          applicable.css('li').select { |item| clean(item).include?('月寒屋外競技場弓道場') }.each(&:remove)
          clean(applicable)
        end : []
        if heading && conditions.any? { |text| text.include?('別途使用料') } && conditions.any? { |text| text.include?('入場料を徴収する場合') }
          price = ([ '専用利用料金（屋外）・平岸庭球場（硬式）', *conditions, table_text(table), OUTDOOR_FEES ]).join("\n")
        end
      end
      hours = content.css('table').find { |node| clean(node).include?('土日祝日') && clean(node).include?('期間') }
      alerts = closure_alerts(content)
      {
        'name' => name, 'address' => "北海道#{details['住所']}", 'prefecture' => '北海道',
        'city' => '札幌市', 'url' => url, 'tag' => '2',
        'tel' => details['電話'], 'sports' => details['ハードコート'].to_s.match?(/\d+面/) ? ['テニス'] : [],
        'access' => section_text(content, '交通アクセス'), 'parking' => details['駐車場'],
        'time' => hours && table_text(hours),
        'regular_holiday' => details['利用期間'].present? ? "利用期間：#{details['利用期間']}（季節営業）" : nil,
        'scale' => details['ハードコート'].present? ? "ハードコート #{details['ハードコート']}" : nil,
        'price' => price, 'alerts' => alerts,
        'evidence' => [{ 'url' => url, 'text' => clean(content) }, { 'url' => OUTDOOR_FEES, 'text' => price }]
      }
    end

    def document(url)
      @robots ||= @client.get("#{ROOT}/robots.txt").lines.filter_map do |line|
        value = line.sub(/#.*/, '').match(/^\s*Disallow:\s*(\S+)/i)&.[](1)
        next if value.blank?
        Regexp.new('\\A' + Regexp.escape(value).gsub('\\*', '.*').sub(/\\\$\z/, '\\z'))
      end
      raise SourceError, 'robots_disallowed' if @robots.any? { |rule| rule.match?(URI.parse(url).path) }
      doc = Nokogiri::HTML(@client.get(url))
      content = doc.at_css('#tmp_contents')
      raise SourceError, 'missing_facility_metadata' unless content
      content.css('script,style,nav,form,#tmp_inquiry,#tmp_social_plugins,#tmp_wrap_ut,#tmp_gmap_link').remove
      content
    end

    def clean(node)
      return '' unless node
      copy = node.dup
      copy.css('br').each { |br| br.replace(' ') }
      copy.text.gsub(/[[:space:]\u00a0]+/, ' ').strip
    end

    def table_details(content)
      content.css('tr').each_with_object({}) do |row, result|
        cells = row.element_children
        result[clean(cells[0])] = clean(cells[1]) if cells.size == 2
      end
    end

    def table_text(table)
      grid = []
      table.css('tr').each_with_index do |row, y|
        raise SourceError, 'missing_facility_metadata' if y > 200
        grid[y] ||= []
        x = 0
        row.element_children.each do |cell|
          x += 1 while grid[y][x]
          width = (cell['colspan'] || '1').to_i
          height = (cell['rowspan'] || '1').to_i
          unless (1..20).cover?(width) && (1..20).cover?(height) && x + width <= 50
            raise SourceError, 'missing_facility_metadata'
          end
          height.times do |dy|
            grid[y + dy] ||= []
            width.times { |dx| grid[y + dy][x + dx] = clean(cell) }
          end
          x += width
        end
      end
      grid.map { |row| row.join(' | ') }.join("\n")
    end

    def section_text(content, title)
      heading = content.css('h2,h3').find { |node| clean(node) == title }
      return unless heading
      nodes = heading.xpath('following-sibling::*').take_while { |node| !node.name.match?(/\Ah[123]\z/) }
      nodes.map { |node| clean(node) }.reject(&:blank?).join("\n").presence
    end

    def fee_text
      return @fees if defined?(@fees)
      content = document(FEES)
      gym = content.css('h3').find { |node| clean(node) == '体育館' }
      return @fees = nil unless gym
      nodes = gym.xpath('following-sibling::*').take_while { |node| node.name != 'h3' }
      index = nodes.index { |node| node.name == 'table' }
      return @fees = nil unless index
      applicable = nodes.take(index).map { |node| clean(node) }.join(' ')
      table = nodes[index]
      return @fees = nil unless applicable.include?('各区体育館') && clean(table).match?(/\d[\d,]*円/)
      # Preserve exemption/age proof rules and time-band/add-on fee qualifications.
      qualification = content.css('h2').find { |node| clean(node) == '料金区分' }
      return @fees = nil unless qualification
      prefix = qualification.xpath('following-sibling::*').take_while { |node| node != gym }
      @fees = ([ '個人利用料金（専用利用は別料金）', *prefix.map { |node| node.name == 'table' ? table_text(node) : clean(node) },
        applicable, table_text(table), FEES ]).reject(&:blank?).join("\n")
    end
  end
end
