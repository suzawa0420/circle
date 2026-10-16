# == Schema Information
#
# Table name: links
#
#  id           :bigint           not null, primary key
#  link01_title :string
#  link01_url   :string
#  link02_title :string
#  link02_url   :string
#  link03_title :string
#  link03_url   :string
#  link04_title :string
#  link04_url   :string
#  link05_title :string
#  link05_url   :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  unique_id    :string
#  user_id      :bigint
#
# Indexes
#
#  index_links_on_unique_id  (unique_id) UNIQUE
#  index_links_on_user_id    (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class Link < ApplicationRecord
  include PublicListingOrder
	belongs_to :user

  validates :unique_id,
    presence: true,
    uniqueness: true,
    length: { minimum: 4, maximum: 16 },
    format: {with: /\A[0-9a-zA-Z]+\z/i }

	validates_format_of :link01_url, :allow_blank => true, with: /\A#{URI::regexp(%w(http https))}\z/
	validates_format_of :link01_url, :allow_blank => true, without: /\A(http|https):\/\/bit.ly/
	validates_format_of :link02_url, :allow_blank => true, with: /\A#{URI::regexp(%w(http https))}\z/
	validates_format_of :link02_url, :allow_blank => true, without: /\A(http|https):\/\/bit.ly/
	validates_format_of :link03_url, :allow_blank => true, with: /\A#{URI::regexp(%w(http https))}\z/
	validates_format_of :link03_url, :allow_blank => true, without: /\A(http|https):\/\/bit.ly/
	validates_format_of :link04_url, :allow_blank => true, with: /\A#{URI::regexp(%w(http https))}\z/
	validates_format_of :link04_url, :allow_blank => true, without: /\A(http|https):\/\/bit.ly/
	validates_format_of :link05_url, :allow_blank => true, with: /\A#{URI::regexp(%w(http https))}\z/
	validates_format_of :link05_url, :allow_blank => true, without: /\A(http|https):\/\/bit.ly/

end
