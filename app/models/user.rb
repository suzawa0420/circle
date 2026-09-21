# == Schema Information
#
# Table name: users
#
#  id                :bigint           not null, primary key
#  age               :string
#  appeal            :text
#  area              :string
#  average_age       :string
#  cb_point          :float            default(0.0), not null
#  contact           :string
#  cost              :string
#  decade_age        :integer
#  email             :string
#  failed_attempts   :integer          default(0), not null
#  foundation        :string
#  gallery_01        :string
#  gallery_02        :string
#  gallery_03        :string
#  gallery_04        :string
#  goal              :string
#  grouping          :string
#  header_image      :string
#  image_name        :string
#  impressions_count :integer          default(0)
#  instagram         :string
#  item              :string
#  last_post         :string
#  line_count        :integer          default(0)
#  locked_at         :datetime
#  mail_count        :integer          default(0)
#  member            :string
#  name              :string
#  ng_account        :string
#  password          :string
#  pic_header        :string
#  pic_profile       :string
#  point             :string
#  prefecture        :string
#  recruitment       :string
#  requirement       :text
#  review_permit     :boolean          default(TRUE)
#  review_score      :string
#  schedule          :string
#  sent_count        :integer
#  switch            :string
#  template          :text
#  twitter           :string
#  unlock_token      :string
#  user_time         :string
#  web               :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  admin_user_id     :bigint
#  category_id       :string
#  event_id          :integer
#  line_id           :string
#  prefecture_id     :bigint
#  prefecture_sub_id :integer
#  unique_id         :string
#  user_id           :string
#
# Indexes
#
#  index_users_on_admin_user_id  (admin_user_id)
#  index_users_on_prefecture_id  (prefecture_id)
#  index_users_on_unlock_token   (unlock_token) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (prefecture_id => prefectures.id)
#
class User < ApplicationRecord
	has_many :blogs, dependent: :destroy
	has_many :schedules, dependent: :destroy
	has_many :places
	has_many :opinions
	has_many :questions, dependent: :destroy
	has_many :collections, dependent: :destroy
	has_many :reviews, dependent: :destroy
	has_many :users_ages, dependent: :destroy
  has_many :ages, through: :users_ages
	has_many :users_groups, dependent: :destroy
  has_many :groups, through: :users_groups
	has_many :users_cities, dependent: :destroy
  has_many :cities, through: :users_cities
	has_many :user_tags, dependent: :destroy
  has_many :tags, through: :user_tags
  has_many :bookmarks, dependent: :destroy
	has_many :user_contacts, dependent: :destroy


	has_one :match, dependent: :destroy
	has_one :link, dependent: :destroy
  accepts_nested_attributes_for :link


	belongs_to :prefecture
	belongs_to :prefecture_sub, class_name: 'Prefecture', foreign_key: 'prefecture_sub_id', optional: true
	belongs_to :category, optional: true
	belongs_to :event
  counter_culture :event, column_name: 'users_count'
	belongs_to :admin_user, optional: true

	with_options presence: true do
    validates :name
    validates :event_id
    validates :prefecture_id
	end

	validates :line_id, {
    :allow_blank => true,
    :format => /\A#{URI::regexp(%w(http https))}\z/
	}

	validates :web, {
    :allow_blank => true,
    :format => /\A#{URI::regexp(%w(http https))}\z/
	}

	NGWORD = %w(http)
	NGWORD_REGEX = %r(#{NGWORD.join('|')})
	validates :template, format: { without: NGWORD_REGEX }

	NG_WORDS = %w(出張館 密会 援交 デリヘル 風俗 売春 援助 AV 풍속 escort)
	NG_REGEX = /#{NG_WORDS.join('|')}/i
	validates :name,   format: { without: NG_REGEX, message: "に使用できない言葉が含まれています" }
	validates :appeal, format: { without: NG_REGEX, message: "に使用できない言葉が含まれています" }, allow_blank: true
	validates :goal,   format: { without: NG_REGEX, message: "に使用できない言葉が含まれています" }, allow_blank: true

	paginates_per 20

	before_save do
		self.average_age.gsub!(/[\[\]\"]/, "") if attribute_present?("average_age")
		self.grouping.gsub!(/[\[\]\"]/, "") if attribute_present?("grouping")
	end

	mount_uploader :pic_profile, ImageUploader
	mount_uploader :pic_header, ImageUploader
	mount_uploader :gallery_01, ImageUploader
	mount_uploader :gallery_02, ImageUploader
	mount_uploader :gallery_03, ImageUploader
	mount_uploader :gallery_04, ImageUploader

  # 新User用
  scope :list, -> {(where(ng_account: nil).or(User.where(ng_account: "OK")).where.not(switch: "").where.not(appeal: "")).includes([:event, :prefecture, :tags, :reviews])}
  scope :where_pref, -> (prefecture_id){where(prefecture_id: prefecture_id).or(User.where(prefecture_sub_id: prefecture_id)).or(User.where(prefecture_id: 50))}
  scope :where_city, -> (city){where(id: city.users.ids).or(User.where(prefecture_id: 50))}
  scope :sort_1, -> {order(switch: :asc, last_post: :desc)}
  scope :sort_2, -> {order(switch: :asc, cb_point: :desc, last_post: :desc)}
  scope :sort_3, -> {order(switch: :asc, created_at: :desc)}
  scope :users_list, -> {(where(ng_account: nil).or(User.where(ng_account: "OK")).where.not(switch: "").where.not(appeal: ""))}


	# User用
  scope :ng_account, -> {(where(ng_account: nil).or(User.where(ng_account: "OK"))).includes([:event, :prefecture, :tags, :reviews])}
  scope :user_sort_1, -> {ng_account.order(switch: :asc, last_post: :desc).where.not(switch: "") }
  scope :user_sort_2, -> {ng_account.order(switch: :asc, cb_point: :desc, last_post: :desc).where.not(switch: "") }
  scope :user_sort_3, -> {ng_account.order(switch: :asc, created_at: :desc).where.not(switch: "") }
  scope :pref, -> { includes(:prefecture).order("prefectures.sort asc") }
  scope :user, -> (user_id){ where(id: user_id) }
  scope :event, -> (event_id){ where(event_id: event_id) }
  scope :prefecture, -> (prefecture_id){ where(prefecture_id: prefecture_id) }
  scope :prefecture_sub, -> (prefecture_sub_id){ where(prefecture_sub_id: prefecture_sub_id) }
  scope :prefecture_50, -> { where(prefecture_id: 50).or(User.where(prefecture_sub_id: 50)) }
  scope :city, -> (city_id){ where(id: city_id) }
  scope :tag, -> (tag_id){ where(id: tag_id) }

  # Blog用
  scope :user_hide, -> { ng_account.where.not(switch: "") }

  # 検索用
	scope :search_word, ->(keyword) do
    where("LOWER(name) LIKE ?", "%#{keyword.downcase}%").
		or(where("schedule LIKE ?", "%#{keyword}%")).
		or(where("area LIKE ?", "%#{keyword}%")).
		or(where("recruitment LIKE ?", "%#{keyword}%")).
		or(where("member LIKE ?", "%#{keyword}%")).
		or(where("cost LIKE ?", "%#{keyword}%")).
		or(where("goal LIKE ?", "%#{keyword}%")).
		or(where("grouping LIKE ?", "%#{keyword}%")).
		or(where("average_age LIKE ?", "%#{keyword}%")).
		or(where("LOWER(appeal) LIKE ?", "%#{keyword.downcase}%"))
	end

	# Tag用
  scope :user_order, -> { includes(:prefecture).order("prefectures.sort asc", switch: :asc, last_post: :desc) }
  scope :user_sort, -> { user_hide.user_order }
  scope :grouping, ->(group_name) do
    where("grouping LIKE ?", "%#{group_name}%")
  end
  scope :average_age, ->(age_name) do
    where("average_age LIKE ?", "%#{age_name}%")
  end
	scope :tag_word, ->(tag_keyword) do
		where("name LIKE ?", "%#{tag_keyword}%").
		or(where("schedule LIKE ?", "%#{tag_keyword}%")).
		or(where("area LIKE ?", "%#{tag_keyword}%")).
		or(where("recruitment LIKE ?", "%#{tag_keyword}%")).
		or(where("member LIKE ?", "%#{tag_keyword}%")).
		or(where("cost LIKE ?", "%#{tag_keyword}%")).
		or(where("goal LIKE ?", "%#{tag_keyword}%")).
		or(where("grouping LIKE ?", "%#{tag_keyword}%")).
		or(where("average_age LIKE ?", "%#{tag_keyword}%")).
		or(where("appeal LIKE ?", "%#{tag_keyword}%"))
	end




  def bookmarked_by?(member)
    bookmarks.where(member_id: member).exists?
  end

end
