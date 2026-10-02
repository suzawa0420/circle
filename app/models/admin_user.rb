# == Schema Information
#
# Table name: admin_users
#
#  id                     :bigint           not null, primary key
#  age                    :string
#  check                  :integer
#  email                  :string           default(""), not null
#  encrypted_password     :string           default(""), not null
#  gender                 :string
#  image_profile          :string
#  moderator              :boolean          default(FALSE), not null
#  nickname               :string
#  open                   :integer          default(0), not null
#  profile                :text
#  remember_created_at    :datetime
#  reset_password_sent_at :datetime
#  reset_password_token   :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  prefecture_id          :bigint
#
# Indexes
#
#  index_admin_users_on_email                 (email) UNIQUE
#  index_admin_users_on_prefecture_id         (prefecture_id)
#  index_admin_users_on_reset_password_token  (reset_password_token) UNIQUE
#
class AdminUser < ApplicationRecord
  include AccountModeration
  include AdminUserDecorator
  before_update :reset_email_verification, if: :will_save_change_to_email?

  def email_verified?
    email_verified_at.present?
  end

  def email_verification_purpose
    "organizer-email:#{Digest::SHA256.hexdigest(email.downcase)}"
  end

  def reset_email_verification
    self.email_verified_at = nil
    self.verification_sent_at = nil
  end

  has_many :users, dependent: :destroy
  belongs_to :prefecture, optional: true

  # accepts_nested_attributes_for :user

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
        :recoverable, :rememberable, :validatable

    validates :nickname, length: { maximum: 16 }

    mount_uploader :image_profile, ImageUploader

  def remember_me
    true
  end

  SHADOW_BANNED_CHECK = 3

  scope :publicly_visible, -> { where(check: nil).or(where.not(check: SHADOW_BANNED_CHECK)) }

  def publicly_visible?
    check != SHADOW_BANNED_CHECK
  end

  # Organizer accounts never grant site administration privileges.
  def master_account?
    false
  end

  alias_method :super_admin?, :master_account?
  alias_method :moderator?, :master_account?
end
