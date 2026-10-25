module PlaceImports
  # Read only the facility-specific summary, access section and labelled rates.
  # Keep weekday/area/person distinctions and table spans when rendering prices.
  class SetagayaDetails
    def call(document, facilities)
      summary = document.css('.c-summaryTable__item').to_h do |row|
        [text(row.at_css('dt')), text(row.at_css('dd'))]
      end
      scale = facilities.filter_map do |facility|
        value = basic_information(facility[:document])
        "#{facility[:label]}\n#{value}" if value.present?
      end.join("\n\n")
      prices = facilities.flat_map do |facility|
        facility[:document].css('h2,h3').filter_map do |heading|
          next unless text(heading).match?(/\A(?:利用料金|利用時間及び利用料金)\z/)
          value = section_text(heading)
          # A link or an empty table alone is not a confirmed numeric price.
          next unless value.match?(/\d[\d,，]*\s*円|無料/)
          group = heading.ancestors.find { |node| node['class'].to_s.split.include?('useTabpanel_contents') }
          kind = if group&.[]('class').to_s.split.include?('person')
            '個人利用'
          elsif group&.[]('class').to_s.split.include?('group')
            '団体利用'
          end
          [facility[:label], kind, value, "公式料金：#{facility[:url]}"].compact.join("\n")
        end
      end
      if prices.any?
        prices << "利用資格：#{summary['利用資格']}" if summary['利用資格'].present?
        prices << "確認日：#{Date.current.iso8601}。最新の利用条件は公式料金ページでご確認ください。"
      end
      {
        'access' => access(document), 'parking' => summary['駐車場'],
        'time' => summary['開館時間'], 'regular_holiday' => summary['休館日'],
        'scale' => scale.presence, 'price' => prices.join("\n\n").presence
      }
    end

    def basic_information(document)
      heading = document.css('h2,h3').find { |h| text(h) == '基本情報' }
      section_text(heading, basic: true)
    end

    private

    def text(node)
      return '' unless node
      copy = node.dup
      copy.css('script,style,nav,form').remove
      copy.css('br').each { |br| br.replace("\n") }
      copy.css('p,li').each { |block| block.add_next_sibling(Nokogiri::XML::Text.new("\n", copy.document)) }
      copy.text.gsub(/[\t\r\f\v\u00a0 ]+/, ' ').split("\n").map(&:strip).reject(&:empty?).join("\n")
    end

    def access(document)
      routes = document.css('.p-facility-singleTab__accessPublicItem').map do |route|
        route.css('.p-facility-singleTab__accessPublicItemPoint2, .p-facility-singleTab__accessPublicItemMeans, .p-facility-singleTab__accessPublicItemUntilArrival').map do |part|
          text(part).gsub(/\s+/, ' ')
        end.reject(&:blank?).join(' → ')
      end
      routes.reject(&:blank?).join(' ／ ').presence
    end

    def section_text(heading, basic: false)
      return '' unless heading
      level = heading.name.delete_prefix('h').to_i
      node = heading.next_element
      parts = []
      while node && !(node.name.match?(/\Ah[1-6]\z/) && node.name.delete_prefix('h').to_i <= level)
        break if basic && (node['class'].to_s.split.include?('useTab') || node.css('h1,h2,h3').any?)
        copy = node.dup
        # Each table becomes a rectangular text grid. Spanning headers repeat,
        # so a number cannot silently lose its weekday or half/full-court label.
        tables = copy.name == 'table' ? [copy] : copy.css('table').to_a
        if copy.name == 'table'
          parts << table_text(copy)
        else
          tables.each { |table| table.replace(Nokogiri::XML::Text.new("\n#{table_text(table)}\n", copy.document)) }
          parts << text(copy)
        end
        node = node.next_element
      end
      parts.reject(&:blank?).join("\n")
    end

    def table_text(table)
      grid = []
      table.xpath('./tr | ./thead/tr | ./tbody/tr | ./tfoot/tr').each_with_index do |row, y|
        grid[y] ||= []
        x = 0
        row.element_children.select { |cell| cell.name.in?(%w[td th]) }.each do |cell|
          x += 1 while grid[y][x]
          width = [cell['colspan'].to_i, 1].max
          height = [cell['rowspan'].to_i, 1].max
          raise SetagayaSource::SourceError, 'unsupported_rate_table' if width > 20 || height > 100
          value = text(cell).gsub(/\s+/, ' ')
          height.times do |dy|
            grid[y + dy] ||= []
            width.times { |dx| grid[y + dy][x + dx] = value }
          end
          x += width
        end
      end
      grid.map { |row| row.map(&:to_s).join(' | ') }.join("\n")
    end
  end
end
