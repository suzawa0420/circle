# == Schema Information
#
# Table name: members
#
#  id                     :bigint           not null, primary key
#  age                    :string
#  email                  :string           default(""), not null
#  encrypted_password     :string           default(""), not null
#  gender                 :string
#  image_profile          :string
#  last_get_point_at      :datetime
#  living_address         :string
#  living_city            :string
#  nickname               :string
#  points                 :integer          default(0), not null
#  profile                :text
#  remember_created_at    :datetime
#  reset_password_sent_at :datetime
#  reset_password_token   :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  living_prefecture_id   :integer
#  prefecture_id          :bigint
#  random_id              :string
#
# Indexes
#
#  index_members_on_email                 (email) UNIQUE
#  index_members_on_prefecture_id         (prefecture_id)
#  index_members_on_reset_password_token  (reset_password_token) UNIQUE
#
class Member < ApplicationRecord
  include AccountModeration
  has_many :conversations, dependent: :destroy
  has_many :received_conversation_reviews, -> { publicly_visible.where(author_role: 'owner') }, through: :conversations, source: :conversation_reviews
  before_update :reset_email_verification, if: :will_save_change_to_email?
  validates :nickname, length: { maximum: 30 }
  validates :nickname, :prefecture, :events, presence: true, on: :profile
  validates :profile, length: { maximum: 2000 }
  validate :valid_date_of_birth
  validate :validate_profile_language, if: -> { will_save_change_to_profile? || validation_context == :profile }

  def japanese_profile?
    return true if profile.blank?
    ActionView::Base.full_sanitizer.sanitize(profile.to_s).unicode_normalize(:nfkc).match?(User::JAPANESE_TEXT)
  end

  def validate_profile_language
    errors.add(:profile, 'は必ず日本語（ひらがな・カタカナを含む文章）でお書きください') unless japanese_profile?
  end

  # Calculate on each read so the displayed decade changes after birthdays.
  def age_group(on: Date.current)
    return if date_of_birth.nil? || date_of_birth > on
    years = on.year - date_of_birth.year
    years -= 1 if on.month < date_of_birth.month || (on.month == date_of_birth.month && on.day < date_of_birth.day)
    years < 10 ? '10歳未満' : "#{years / 10 * 10}代"
  end

  def valid_date_of_birth
    if date_of_birth.nil? && date_of_birth_before_type_cast.present?
      errors.add(:date_of_birth, 'を正しい日付で入力してください')
    elsif date_of_birth && (date_of_birth > Date.current || date_of_birth < Date.new(1900, 1, 1))
      errors.add(:date_of_birth, 'は1900年1月1日から今日までの日付を入力してください')
    end
  end

  def email_verified?
    email_verified_at.present?
  end

  def email_verification_purpose
    "chat-email:#{Digest::SHA256.hexdigest(email.downcase)}"
  end

  def received_review_score
    received_conversation_reviews.average(:score).to_f * 5
  end

  def reset_email_verification
    self.email_verified_at = nil
    self.verification_sent_at = nil
  end

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
          :recoverable, :rememberable, :validatable

	# has_many :event_answers
	has_many :reviews, dependent: :destroy
  has_many :bookmarks, dependent: :destroy
  has_many :members_events, dependent: :destroy
  has_many :events, through: :members_events
  has_many :applications

  belongs_to :prefecture, optional: true

  mount_uploader :image_profile, ImageUploader

  def remember_me
    true
  end

  def can_apply?
    last_application = applications.order(applied_at: :desc).first
    return true if last_application.nil?
    last_application.applied_at < 1.month.ago
  end

end
