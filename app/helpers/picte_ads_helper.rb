module PicteAdsHelper
  def picte_camera_event?(event)
    event&.ruby == 'camera'
  end

  def picte_ad_url(placement)
    content = { 'search' => 'camera_search_v1', 'mypage' => 'organizer_mypage_v1' }.fetch(placement)
    'https://picte-photo.com/service/share-exhibition/?' + {
      utm_source: 'circlebook', utm_medium: 'display', utm_campaign: 'picte_share_exhibition', utm_content: content
    }.to_query
  end
end
