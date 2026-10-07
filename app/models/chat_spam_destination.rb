class ChatSpamDestination < ApplicationRecord
  validates :destination, presence: true, uniqueness: true, length: { maximum: 2048 }
end
