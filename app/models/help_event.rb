class HelpEvent < ApplicationRecord
  validates :kind, inclusion: { in: %w[search helpful unhelpful] }
  validates :query, length: { maximum: 100 }
  validates :visitor_key, :recorded_on, presence: true
end
