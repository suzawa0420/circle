# == Schema Information
#
# Table name: places
#
#  id                  :bigint           not null, primary key
#  access              :string
#  address             :string
#  average_access      :float
#  average_facility    :float
#  average_price       :float
#  average_reservation :float
#  average_score       :float
#  img_link            :string
#  img_source          :string
#  img_url             :string
#  name                :string
#  parking             :string
#  price               :string
#  regular_holiday     :string
#  scale               :string
#  sns                 :text
#  tag                 :string
#  tel                 :string
#  time                :string
#  url                 :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  city_id             :integer
#  event_id            :integer
#  prefecture_id       :integer
#  user_id             :integer
#
class Place < ApplicationRecord
	belongs_to :prefecture
  counter_culture :prefecture, column_name: 'places_count'
	belongs_to :city
  counter_culture :city, column_name: 'places_count'
	belongs_to :user, optional: true

  has_many :place_reviews, dependent: :destroy
  has_many :public_place_reviews, -> { where(moderation_status: "clear") }, class_name: "PlaceReview"
  has_many :places_events, dependent: :destroy
  has_many :events, through: :places_events

  validates :prefecture_id, presence: true
  validates :event_ids, presence: true

  validates :name, presence: true
  validates :name, uniqueness: true
  validates :tag, presence: true
  validates :address, presence: true

  paginates_per 10

  def refresh_review_scores!
    averages = %i[facility reservation price access].to_h do |key|
      ["average_#{key}", public_place_reviews.average(key)&.to_f]
    end
    score = averages.values.all? ? averages.values.sum / 4.0 : nil
    update_columns(averages.merge("average_score" => score, "updated_at" => Time.current))
  end

  # Place_検索用
	scope :place_search_word, ->(keyword) do
    where("LOWER(name) LIKE ?", "%#{keyword.downcase}%").
		or(where("address LIKE ?", "%#{keyword}%")).
		or(where("parking LIKE ?", "%#{keyword}%")).
		or(where("scale LIKE ?", "%#{keyword}%")).
		or(where("access LIKE ?", "%#{keyword}%"))
	end

end
