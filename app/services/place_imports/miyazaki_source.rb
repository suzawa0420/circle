require 'digest'

module PlaceImports
  # A deliberately small, manually reviewed pilot. Facts are published only while
  # ALL reviewed visible text, links, images and tariff cell spans remain unchanged.
  # Changed news/qualifications fail closed; never infer safety from a familiar title.
  class MiyazakiSource
    KEY = 'miyazaki_ikimeno'.freeze
    ROOT = 'https://ikimenomori.jp'.freeze
    URL = "#{ROOT}/facilities/facilities07/".freeze
    REVIEWED_ON = '2026-11-09'.freeze
    PHOTO_URL = "#{ROOT}/wp-content/themes/ikime_theme/images/facilities_img07.jpg".freeze
    class SourceError < StandardError; end

    def initialize(client: MiyazakiClient.new); @client = client; end
    def key; KEY; end
    def revalidate_before_apply?; true; end
    def seeds; [{ 'url' => URL }]; end
    def discover; raise SourceError, 'partial_reviewed_seed_only'; end

    def fetch(url)
      raise SourceError, 'unapproved_facility_url' unless url == URL
      # Conservative across all user-agent groups. No identity spoofing or Allow override.
      robots = @client.get("#{ROOT}/robots.txt").lines.filter_map do |line|
        rule = line.sub(/#.*/, '').match(/^\s*Disallow:\s*(\S+)/i)&.[](1)
        Regexp.new('\\A' + Regexp.escape(rule).gsub('\\*', '.*').sub(/\\\$\z/, '\\z')) if rule.present?
      end
      pages = MiyazakiClient::REVIEW.to_h do |review|
        path = review.fetch('path')
        raise SourceError, 'robots_disallowed' if robots.any? { |rule| rule.match?(path) }
        doc = Nokogiri::HTML(@client.get("#{ROOT}#{path}"))
        doc.css('script,style').remove
        body = doc.at_css('body')
        raise SourceError, 'missing_facility_metadata' unless body && doc.css('#footer').one? && doc.css(path == '/' ? '#indexmain' : '#main').one?
        raise SourceError, 'unreviewed_source_change' unless fingerprint(body) == review.fetch('sha256')
        [path, doc]
      end
      # All figures are factual paraphrases of the fingerprinted HTML tables.
      # The 7/4 outage is superseded by the explicit 7/25 court/night-light recovery.
      # The temporary-parking notice ended 11/1. Shower eligibility is preserved below.
      {
        'name' => 'アイ・ホームテニスコート（生目の杜運動公園）',
        'address' => '宮崎県宮崎市大字跡江4461番地1', 'prefecture' => '宮崎県', 'city' => '宮崎市',
        'tag' => '2', 'sports' => ['テニス'], 'url' => URL, 'tel' => '0985-47-6222',
        'time' => '9:00～22:00。開場している水曜日は17:00まで。',
        'regular_holiday' => '12月29日～1月3日、第4水曜日（水曜日が休日の場合は翌日）。',
        'scale' => '屋外の砂入り人工芝16面（16面にナイター照明）。テニス・ソフトテニス用。運営棟・屋根付きスタンドあり。シャワーは有料施設利用者のみ、事務所で受付。',
        'access' => '生目の杜運動公園へのアクセス（コート入口までの所要時間ではありません）。宮崎西ICから車で約5分、宮崎駅から約20分、宮崎空港から約30分。体育館前「生目の杜運動公園」停留所：宮交シティから記念病院・生目の杜行き（土日祝のみ）。多目的グラウンドA側「生目の杜運動公園北」停留所：宮交シティまたは宮崎駅から小松台・悠楽園経由、宮崎中央営業所行き。',
        'parking' => '運動公園の駐車場あり。1利用につき自動車100円（大型バス・マイクロバス・自動二輪車以外）、大型バス200円（定員30人以上）、マイクロバス200円（定員11人以上30人未満）。土日祝またはソフトバンクホークスキャンプの10:00～18:00の利用時に限り徴収。台数は未掲載。',
        'price' => "1面1時間。入場料を徴収しない場合：アマチュアは中学生以下240円、高校生350円、一般700円。アマチュア以外3,500円。入場料を徴収する場合：アマチュアは中学生以下480円、高校生700円、一般1,400円。アマチュア以外7,000円。照明は1面1時間、アマチュア510円、それ以外2,550円。テニスコート運営棟は1時間340円。\n公式料金：#{URL}\n確認日：#{Date.current.iso8601}",
        'alerts' => [],
        'evidence' => pages.map do |path, doc|
          content = doc.at_css(path == '/' ? '#indexmain' : '#main')
          { 'url' => "#{ROOT}#{path}", 'text' => clean(content) }
        end + [{ 'url' => PHOTO_URL, 'text' => "#{REVIEWED_ON} 公式写真を目視確認：屋外。画像URLと施設名・16面の記載を照合。画像は転載しない。" }]
      }
    end

    private

    def clean(node)
      node.text.gsub(/[[:space:]\u00a0]+/, ' ').strip
    end

    def fingerprint(body)
      signature = [clean(body), body.css('a').map { |n| [clean(n), n['href']] },
        body.css('img').map { |n| [n['alt'], n['src']] },
        body.css('table').map { |table| table.css('tr').map { |row| row.css('th,td').map { |cell| [clean(cell), cell['rowspan'], cell['colspan']] } } }]
      Digest::SHA256.hexdigest(JSON.generate(signature))
    end
  end
end
