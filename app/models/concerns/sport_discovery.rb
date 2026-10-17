module SportDiscovery
  extend ActiveSupport::Concern

  DETAIL_FIELDS = {
    'activity_style' => '活動スタイル（例：ポタリング・低山ハイキング）',
    'experience' => '参加レベル・経験の目安',
    'trial' => '体験参加・一人参加について',
    'equipment' => '道具の貸出・持ち物',
    'meeting_area' => '集合・出発場所',
    'destination' => '主な活動先（ゲレンデ・コートなど）',
    'trip_type' => '日帰り・宿泊などの活動形式'
  }.freeze

  included do
    store_accessor :sport_details, *DETAIL_FIELDS.keys
    validate :valid_sport_details
    scope :for_event, ->(events) do
      ids = if events.is_a?(ActiveRecord::Relation)
              events.pluck(:id)
            else
              Array(events).map { |event| event.respond_to?(:id) ? event.id : event }
            end
      where(event_id: ids)
    end
  end

  def public_sport_details
    DETAIL_FIELDS.filter_map { |key, label| [label, sport_details[key]] if sport_details[key].present? }
  end

  private

  def valid_sport_details
    DETAIL_FIELDS.each_key do |key|
      value = sport_details[key]
      errors.add(:base, "#{DETAIL_FIELDS[key]}は200文字以内で入力してください") unless value.nil? || (value.is_a?(String) && value.length <= 200)
    end
  end
end
