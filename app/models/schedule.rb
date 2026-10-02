# == Schema Information
#
# Table name: schedules
#
#  id                  :bigint           not null, primary key
#  cost                :string
#  date                :string
#  day                 :string
#  google_map          :string
#  member_venue        :string
#  note                :text
#  recruitment         :string
#  recruitment_numbers :integer
#  time_e              :time
#  time_s              :time
#  title               :string
#  top_image           :string
#  venue               :string
#  venue_address       :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  user_id             :bigint
#
# Indexes
#
#  index_schedules_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class Schedule < ApplicationRecord
  include RemembersCircleActivity
  belongs_to :user
	has_many :name_schedules, dependent: :destroy
  has_many :names, through: :name_schedules
  validates :day, presence: true, date: true
  validates :venue, presence: true
  validates :title, presence: true

	paginates_per 5

	mount_uploader :top_image, ImageUploader


end
