module PrefecturesHelper
  PREFECTURE_REGIONS = {
    '全国・オンライン' => %w[全国 オンライン],
    '北海道エリア' => %w[北海道],
    '東北エリア' => %w[青森県 岩手県 宮城県 秋田県 山形県 福島県],
    '関東エリア' => %w[茨城県 栃木県 群馬県 埼玉県 千葉県 東京都 神奈川県],
    '中部エリア' => %w[新潟県 富山県 石川県 福井県 山梨県 長野県 岐阜県 静岡県 愛知県],
    '関西エリア' => %w[三重県 滋賀県 京都府 大阪府 兵庫県 奈良県 和歌山県],
    '中国エリア' => %w[鳥取県 島根県 岡山県 広島県 山口県],
    '四国エリア' => %w[徳島県 香川県 愛媛県 高知県],
    '九州・沖縄エリア' => %w[福岡県 佐賀県 長崎県 熊本県 大分県 宮崎県 鹿児島県 沖縄県]
  }.transform_values(&:freeze).freeze

  def prefecture_option_groups(prefectures)
    grouped = prefectures.group_by do |prefecture|
      PREFECTURE_REGIONS.find { |_region, names| names.include?(prefecture.name) }&.first || 'その他のエリア'
    end
    (PREFECTURE_REGIONS.keys + ['その他のエリア']).filter_map do |region|
      [region, grouped[region]] if grouped[region].present?
    end
  end
end
