require 'digest'

module PlaceImports
  class KochiSource
    KEY = 'kochi_sports'.freeze
    ROOT = 'https://www.kc-sports.or.jp'.freeze
    URL = "#{ROOT}/facilities/f300/f305/".freeze
    PDF_URL = "#{ROOT}#{KochiClient::PDF_PATH}".freeze
    PDF_SHA256 = '33d9dc7e34d86b579d30c235bf368c4994ddd2556ea09630f3f9a065c7c68309'.freeze
    NOTICE_TEXT_SHA256 = '97dec69ff97873abecf4261f97321d02a8f9b52c4622c570d0cd672a3dd7d0f1'.freeze
    REVIEWED_ON = '2026-11-07'.freeze
    PHOTO_URL = 'https://kc-sports.or.jp/uploads/5a0249179c877292721cf38b7f67ba91.jpg'.freeze
    NAME = '東部総合運動場テニスコート'.freeze
    # Visual review of the exact official photograph established outdoor use.
    # This static classification is guarded by live name/address/count/photo identity.
    TARIFF = <<~TEXT.freeze
      利用料金（入場料・会費等を徴収しない団体利用、1面、税込）。
      高校生以下：1時間530円、午前8:00～12:00 1,350円、午後13:00～17:00 1,350円、1日8:00～17:00 2,700円。
      その他：1時間780円、午前8:00～12:00 2,360円、午後13:00～17:00 2,360円、1日8:00～17:00 4,720円。
      テニスコートの照明（コイン式）：1面12分100円。クラブハウス：1時間550円。シャワー：1回10分100円。
      1円代の端数は切捨て。2026年4月1日からの利用申請分に適用。
      入場料・会費等を徴収する場合は、この料金表の対象外。PDF記載時点：令和8年4月1日時点。
    TEXT
    # Only these exact unrelated notices were reviewed. Changed titles/links are
    # not silently dismissed, and no arbitrary news URL is ever fetched.
    UNRELATED_NOTICES = {
      '/i1002026009/' => '日本トーター総合体育館 室内プール休業のお知らせ',
      '/i1002026005/' => '日本トーター総合運動場テニスコート休業のお知らせ',
      '/i1002026008/' => '日本トーター総合体育館 主競技場・補助競技場・ランニング走路 休業のお知らせ',
      '/i1002026007/' => '日本トーター総合運動場 陸上競技場休業のお知らせ',
      '/i1002026004/' => '日本トーター総合運動場 多目的ドーム休業のお知らせ'
    }.freeze
    WARNING = /閉館|閉鎖|休館|休業|休止|停止|利用制限|利用不可|工事|改修|料金.*(?:改定|変更)/
    class SourceError < StandardError; end

    def initialize(client: KochiClient.new); @client = client; end
    def key; KEY; end
    def seeds; [{ 'url' => URL }]; end
    def discover; raise SourceError, 'partial_reviewed_seed_only'; end

    def fetch(url)
      raise SourceError, 'unapproved_facility_url' unless url == URL
      # Recheck robots on every run, including repeated calls on one source.
      @disallowed = @client.get("#{ROOT}/robots.txt").lines.filter_map do |line|
        rule = line.sub(/#.*/, '').match(/^\s*Disallow:\s*(\S+)/i)&.[](1)
        Regexp.new('\\A' + Regexp.escape(rule).gsub('\\*', '.*').sub(/\\\$\z/, '\\z')) if rule.present?
      end
      pages = %w[/facilities/f300/f305/ /facilities/f300/ /facilities/costs/ /i0002025006/ /].to_h do |path|
        [path, Nokogiri::HTML(get(path))]
      end
      venue = content(pages.fetch('/facilities/f300/f305/'))
      info = venue.css('#tablepress-f305ov-1 tbody tr').to_h do |row|
        cells = row.css('td'); [clean(cells[0]), clean(cells[1])]
      end
      raise SourceError, 'changed_facility_identity' unless clean(venue.at_css('h1')) == NAME &&
        info['住所・電話番号'] == "高知市介良1221-1\nTEL:088-878-1150（くろしおアリーナ事務所）" &&
        info['施設内容'] == '砂入り人工芝全16コート（うちナイター設備は8コート） ※5，6月は1～5番コートのみナイター設備使用可' &&
        venue.css('img').any? { |img| [img['srcset'], img['data-srcset']].compact.any? { |src| src.split(',').any? { |part| part.strip.split.first == PHOTO_URL } } }
      %w[収容人員 夜間照明 駐車場 施設面積 付帯施設 使用時間 休場日 使用可能競技 備品 その他].each do |field|
        raise SourceError, 'missing_facility_metadata' if info[field].blank?
      end
      raise SourceError, 'changed_available_sports' unless info['使用可能競技'] == '硬式テニス，ソフトテニス'
      park = content(pages.fetch('/facilities/f300/'))
      heading = park.at_css('#access_in_page_f300')&.parent
      list = heading&.xpath('following-sibling::ul[1]')&.first
      raise SourceError, 'missing_access' unless clean(heading) == 'アクセス' && list && list.css('li').size == 4 && clean(list).include?('東部野球場前下車徒歩3分')
      rates = content(pages.fetch('/facilities/costs/')).css('a').select { |a| clean(a).include?('東部スポーツパーク') }
      raise SourceError, 'changed_current_rate_link' unless rates.one? && rates.first['href'] == PDF_URL
      notice = content(pages.fetch('/i0002025006/'))
      unless Digest::SHA256.hexdigest(clean(notice)) == NOTICE_TEXT_SHA256
        raise SourceError, 'changed_rate_qualifications'
      end
      pdf = get(KochiClient::PDF_PATH)
      raise SourceError, 'unreviewed_rate_document' unless pdf.bytesize <= KochiClient::MAX_BYTES && Digest::SHA256.hexdigest(pdf) == PDF_SHA256
      alerts = notices(pages.fetch('/'))
      alerts.concat(warnings(venue)).concat(warnings(park))
      {
        'name' => NAME, 'address' => '高知県高知市介良1221-1', 'prefecture' => '高知県', 'city' => nil,
        'tag' => '2', 'sports' => ['テニス'], 'url' => URL, 'tel' => '088-878-1150',
        'access' => "東部総合運動場（親施設）へのアクセス。テニスコート入口までの時間ではありません。\n#{clean(list)}",
        'parking' => info['駐車場'], 'time' => info['使用時間'], 'regular_holiday' => info['休場日'],
        'scale' => ['屋外', *info.except('駐車場', '使用時間', '休場日').map { |label, text| "#{label}：#{text}" }].join("\n"),
        'price' => "#{TARIFF}\n公式料金：#{PDF_URL}\n確認日：#{Date.current.iso8601}",
        'alerts' => alerts.uniq,
        'evidence' => pages.map { |path, doc| { 'url' => "#{ROOT}#{path}", 'text' => clean(content(doc)) } } +
          [{ 'url' => PDF_URL, 'text' => "SHA256: #{PDF_SHA256}\n目視確認日：#{REVIEWED_ON}\n#{TARIFF}" },
           { 'url' => PHOTO_URL, 'text' => "#{REVIEWED_ON} 公式写真を目視確認：屋外。施設名・住所・16面・写真URLを照合。" }]
      }
    end

    private

    def get(path)
      raise SourceError, 'robots_disallowed' if @disallowed.any? { |rule| rule.match?(path) }
      @client.get("#{ROOT}#{path}")
    end

    def content(doc)
      nodes = doc.css('.mainSection .entry-body')
      raise SourceError, 'missing_facility_content' unless nodes.one?
      nodes.first
    end

    def notices(doc)
      body = content(doc).dup
      boxes = body.css('.su-box').select { |box| clean(box.at_css('.su-box-title')) == '新着情報' }
      raise SourceError, 'unverified_notice_structure' unless boxes.one? && boxes.first.css('.su-box-content p').any? { |p| clean(p).match?(/20\d{2}年\d{1,2}月\d{1,2}日/) && p.css('a').any? }
      body.css('a').each do |a|
        path = UNRELATED_NOTICES.find { |path, title| a['href'] == "#{ROOT}#{path}" && clean(a) == title }
        known_rate = a['href'] == "#{ROOT}/i0002025006/" && clean(a) == '利用料金改定のお知らせ'
        a.remove if path || known_rate
      end
      warnings(body)
    end

    def warnings(node)
      copy = node.dup
      copy.css('script,style,nav,form,.veu_socialSet').remove
      blocks = copy.css('a,p,div,td,li,h1,h2,h3,span').select { |block| clean(block).match?(WARNING) }
      blocks.reject { |block| blocks.any? { |other| other != block && other.ancestors.include?(block) } }.map { |block| clean(block) }.uniq
    end

    def clean(node)
      return '' unless node
      copy = node.dup
      copy.css('script,style,nav,form,.veu_socialSet').remove
      copy.css('br').each { |br| br.replace("\n") }
      copy.css('p,li,h1,h2,h3').each { |n| n.add_next_sibling(Nokogiri::XML::Text.new("\n", copy.document)) }
      copy.text.gsub(/[\t\r\f\v\u00a0　 ]+/, ' ').lines.map(&:strip).reject(&:empty?).join("\n")
    end
  end
end
