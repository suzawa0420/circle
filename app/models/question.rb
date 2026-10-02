# == Schema Information
#
# Table name: questions
#
#  id         :bigint           not null, primary key
#  answer     :text
#  content    :text
#  ip_address :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint
#
# Indexes
#
#  index_questions_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class Question < ApplicationRecord
  include RemembersCircleActivity
  belongs_to :user
  validates :content, presence: true, length: { in: 1..80 }

	NGWORD = %w(http 死ね 京築リーグ 株式会社 弊社 副業 先行予約)
	NGWORD_REGEX = %r(#{NGWORD.join('|')})
	validates :content, format: { without: NGWORD_REGEX, message: 'にNGワードが含まれています' }


	paginates_per 10

end
