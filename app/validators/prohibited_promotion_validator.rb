class ProhibitedPromotionValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    # Keep legacy messages deletable/moderatable and account maintenance possible.
    return unless record.will_save_change_to_attribute?(attribute)
    return unless CircleProfilePolicy.prohibited_promotion?(value)

    record.errors.add(attribute, :invalid, message: 'に使用できない言葉が含まれています')
  end
end
