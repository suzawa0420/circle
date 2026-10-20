class PicteAdClickCount < ApplicationRecord
  PLACEMENTS = { 'search' => '写真・カメラの検索結果', 'mypage' => '主催者マイページ' }.freeze

  validates :recorded_on, presence: true
  validates :placement, inclusion: { in: PLACEMENTS.keys }
  validates :click_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def self.record_click!(placement)
    raise ArgumentError unless PLACEMENTS.key?(placement)

    upsert({ recorded_on: Time.current.in_time_zone('Tokyo').to_date, placement: placement, click_count: 1 },
      unique_by: [:recorded_on, :placement],
      on_duplicate: Arel.sql('click_count = picte_ad_click_counts.click_count + 1'))
  end
end
