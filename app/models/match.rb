# == Schema Information
#
# Table name: matches
#
#  id         :bigint           not null, primary key
#  age_group  :string
#  comment    :text
#  level      :string
#  member     :string
#  recruit    :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint
#
# Indexes
#
#  index_matches_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class Match < ApplicationRecord
  include PublicListingOrder
	belongs_to :user
	paginates_per 10
end
