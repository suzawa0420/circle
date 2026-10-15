# == Schema Information
#
# Table name: events
#
#  id          :bigint           not null, primary key
#  category    :string
#  icon        :string
#  matching    :integer
#  name        :string
#  openchat    :string
#  order       :string
#  place       :integer
#  ruby        :string
#  txt         :string
#  users_count :integer          default(0), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  category_id :string
#
class Event < ApplicationRecord
  SEARCH_ALIASES = {
    '軟式テニス' => 'soft-tennis', 'ピックボール' => 'pickleball',
    'サイクリング' => 'road-bike', 'ポタリング' => 'road-bike',
    'ハイキング' => 'mountain', '低山登山' => 'mountain',
    'ウォーキング' => 'go-out', 'ジョギング' => 'running', 'マラソン' => 'running'
  }.freeze

  def self.matching_keyword(keyword)
    matches = where('name LIKE ?', "%#{sanitize_sql_like(keyword)}%")
    SEARCH_ALIASES.key?(keyword) ? matches.or(where(ruby: SEARCH_ALIASES.fetch(keyword))) : matches
  end

	belongs_to :category

	has_many :users
	has_many :event_questions

	has_many :places_events
  has_many :places, through: :places_events
	has_many :members_events
  has_many :members, through: :members_events

end
