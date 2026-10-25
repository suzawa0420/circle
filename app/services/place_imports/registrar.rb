module PlaceImports
  class Registrar
    DETAIL_LABELS = { 'access' => 'アクセス', 'parking' => '駐車場', 'time' => '利用時間',
      'regular_holiday' => '休館日', 'scale' => '施設規模', 'price' => '料金' }.freeze
    SPORT_ALIASES = { 'バスケットボール' => %w[バスケ バスケットボール], 'バレーボール' => %w[バレー バレーボール] }.freeze

    def self.normalize(value)
      value.to_s.unicode_normalize(:nfkc).downcase.gsub(/[[:space:]‐‑‒–—―−ー－-]/, '').gsub(/丁目|番地?|号/, '')
    end

    def self.canonical_url(value)
      uri = URI.parse(value.to_s)
      return '' unless uri.is_a?(URI::HTTP) && uri.host.present?
      "#{uri.host.downcase.sub(/\Awww\./, '')}#{uri.path.sub(%r{/+\z}, '')}"
    rescue URI::InvalidURIError
      ''
    end

    def call(candidate, apply: false)
      candidate.with_lock do
        return candidate.status if candidate.status.in?(%w[registered dismissed])
        data = candidate.payload
        prefecture = Prefecture.find_by(name: data['prefecture'])
        unless prefecture
          candidate.update!(status: 'pending', reason: '都道府県が一致しません')
          return 'pending'
        end
        # Serializes registration across importer workers, even across hosts.
        prefecture.with_lock do
          matches = duplicate_ids(data, prefecture)
          if matches.any?
            candidate.update!(status: 'duplicate', reason: "既存施設の確認が必要です（ID: #{matches.first(10).join(', ')}）")
            return 'duplicate'
          end
          city = prefecture.cities.find_by(name: data['city'])
          events = Array(data['sports']).map do |name|
            Event.where(place: 1, name: SPORT_ALIASES.fetch(name, [name])).to_a
          end
          reasons = []
          reasons << '公式情報の再取得が必要です' if candidate.checked_at < 7.days.ago
          reasons << '施設名・住所・市区町村・屋内外の区分を確認してください' unless
            data['name'].present? && data['address'].present? && city && data['tag'].in?(%w[1 2]) &&
            self.class.normalize(data['address']).start_with?(self.class.normalize("#{prefecture.name}#{city.name}"))
          reasons << '対応種目を確認してください' if events.empty? || events.any? { |group| group.size != 1 }
          reasons << '休館・閉鎖等のお知らせを確認してください' if Array(data['alerts']).any?
          reasons << '公式の施設情報に根拠がありません' unless Array(data['evidence']).any? { |item| item['text'].present? }
          missing_details = DETAIL_LABELS.filter_map { |key, label| label if data[key].blank? }
          reasons << "詳細情報が未確認です：#{missing_details.join('・')}" if missing_details.any?
          if reasons.any?
            candidate.update!(status: 'pending', reason: reasons.join('／'))
            return 'pending'
          end
          unless apply
            candidate.update!(status: 'pending', reason: '自動登録可能（プレビュー）')
            return 'ready'
          end
          place = Place.create!(name: data['name'], address: data['address'], prefecture: prefecture, city: city,
            events: events.flatten, tag: data['tag'], tel: data['tel'], url: data['url'],
            **data.slice(*DETAIL_LABELS.keys).symbolize_keys)
          candidate.update!(place: place, status: 'registered', reason: '公式情報を確認して登録しました')
          'registered'
        end
      end
    rescue ActiveRecord::RecordInvalid
      candidate.update!(status: 'pending', reason: '登録条件を満たしません。施設管理画面で確認してください')
      'pending'
    end

    private

    def duplicate_ids(data, prefecture)
      name = self.class.normalize(data['name'])
      address = self.class.normalize(data['address'])
      phone = data['tel'].to_s.unicode_normalize(:nfkc).gsub(/\D/, '')
      url = self.class.canonical_url(data['url'])
      Place.where(prefecture_id: prefecture.id).pluck(:id, :name, :address, :tel, :url).filter_map do |id, other_name, other_address, other_phone, other_url|
        n = self.class.normalize(other_name)
        a = self.class.normalize(other_address)
        # Same location/contact may contain multiple courts: retain for review.
        id if (name.present? && n.present? && (name.include?(n) || n.include?(name))) ||
          (address.present? && a.present? && (address.include?(a) || a.include?(address))) ||
          (phone.present? && phone == other_phone.to_s.unicode_normalize(:nfkc).gsub(/\D/, '')) ||
          (url.present? && url == self.class.canonical_url(other_url))
      end
    end
  end
end
