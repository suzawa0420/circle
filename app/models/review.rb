# == Schema Information
#
# Table name: reviews
#
#  id         :bigint           not null, primary key
#  age        :string
#  comment    :text
#  gender     :string
#  ip         :string
#  nickname   :string
#  review     :integer
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  member_id  :bigint
#  user_id    :bigint
#
# Indexes
#
#  index_reviews_on_member_id  (member_id)
#  index_reviews_on_user_id    (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (member_id => members.id)
#  fk_rails_...  (user_id => users.id)
#
class Review < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :member, optional: true

	NGWORD = %w(http 死ね bit й л com link)
	NGWORD_REGEX = %r(#{NGWORD.join('|')})
  validates :comment,
    format: { without: NGWORD_REGEX },
    length: { minimum: 6, maximum: 2000 }
  validates :review, inclusion: { in: [0, 1] }
  validates :comment, format: { without: %r{https?://|www\.}i }

end
