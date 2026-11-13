class PlaceDiscoverySource < ApplicationRecord
  serialize :state, coder: JSON
  validates :prefecture_name, :root_url, presence: true
end
