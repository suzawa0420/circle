class CircleScoreUpdater
  include Circlebook
  def refresh(user)
    cb_point(user)
  end
end
