module RemembersCircleActivity
  extend ActiveSupport::Concern

  included do
    before_update { CircleActivityRecorder.remember(self, previous: true) }
    before_destroy { CircleActivityRecorder.remember(self) }
  end
end
