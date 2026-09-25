# == Schema Information
#
# Table name: place_reviews
#
#  id            :bigint           not null, primary key
#  access        :float
#  average_score :float
#  comment       :text
#  facility      :float
#  ip_address    :string
#  price         :float
#  reservation   :float
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  event_id      :integer
#  place_id      :bigint
#
# Indexes
#
#  index_place_reviews_on_place_id  (place_id)
#
# Foreign Keys
#
#  fk_rails_...  (place_id => places.id)
#
class PlaceReview < ApplicationRecord
  belongs_to :place
  validates :facility, :reservation, :price, :access, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 5 }
  validates :comment, length: { minimum: 6, maximum: 2000 }
  validates :comment, format: { without: %r{https?://|www\.}i }

	with_options presence: true do
    validates :price
    validates :facility
    validates :access
    validates :reservation
    validates :comment
	end

	NGWORD = %w(http 死ね)
	NGWORD_REGEX = %r(#{NGWORD.join('|')})
	validates :comment, format: { without: NGWORD_REGEX }


end
