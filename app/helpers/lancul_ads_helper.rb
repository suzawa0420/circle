module LanculAdsHelper
  def lancul_english_event?(event)
    event&.ruby == 'english'
  end

  def lancul_member_interested?(member)
    member.events.exists?(ruby: 'english')
  end
end
