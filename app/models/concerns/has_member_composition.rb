module HasMemberComposition
  extend ActiveSupport::Concern

  BANDS = { 'teens' => '10代', 'twenties' => '20代', 'thirties' => '30代',
    'forties' => '40代', 'fifties' => '50代', 'sixties_plus' => '60代以上' }.freeze
  PERCENTAGES = (0..100).step(5).to_a.freeze

  included do
    validate :validate_member_age_percentages
    validate :validate_member_male_percentage
  end

  private

  def composition_percentage(value)
    return unless value.is_a?(Integer) || (value.is_a?(String) && value.match?(/\A(?:0|[1-9]\d?|100)\z/))

    number = value.to_i
    number if PERCENTAGES.include?(number)
  end

  def validate_member_age_percentages
    value = member_age_percentages
    return if value.nil?

    unless value.is_a?(Hash) && (value.keys - BANDS.keys).empty?
      return errors.add(:member_age_percentages, 'は指定の年齢区分で入力してください')
    end
    if value.values.all? { |number| number.nil? || number == '' }
      self.member_age_percentages = nil
      return
    end

    percentages = BANDS.keys.index_with do |band|
      raw = value[band]
      raw.nil? || raw == '' ? 0 : composition_percentage(raw)
    end
    if percentages.value?(nil)
      errors.add(:member_age_percentages, 'は0〜100%の範囲で5%刻みにしてください')
    elsif percentages.values.sum != 100
      errors.add(:member_age_percentages, 'の合計を100%にしてください')
    else
      self.member_age_percentages = percentages
    end
  end

  def validate_member_male_percentage
    raw = member_male_percentage_before_type_cast
    return if raw.nil? || raw == '' || composition_percentage(raw)

    errors.add(:member_male_percentage, 'は0〜100%の範囲で5%刻みにしてください')
  end
end
