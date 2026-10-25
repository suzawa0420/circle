class PlaceImportRun < ApplicationRecord
  serialize :summary, coder: JSON
end
