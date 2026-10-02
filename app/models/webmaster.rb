class Webmaster < ApplicationRecord
  devise :database_authenticatable, :validatable, :rememberable, :timeoutable, :lockable,
         timeout_in: 30.minutes, maximum_attempts: 10, unlock_strategy: :time,
         unlock_in: 30.minutes

  validates :id, inclusion: { in: [1] }
  validates :password, length: { minimum: 12 }, if: :password_required?

  def active_for_authentication?
    super && id == 1
  end
end
