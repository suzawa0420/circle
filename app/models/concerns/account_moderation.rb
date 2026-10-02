module AccountModeration
  extend ActiveSupport::Concern
  included do
    validates :suspension_reason, length: { maximum: 2000 }
  end
  def suspended?
    suspended_at.present?
  end
end
