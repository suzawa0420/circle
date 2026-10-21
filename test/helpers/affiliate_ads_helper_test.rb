require 'test_helper'

class AffiliateAdsHelperTest < ActionView::TestCase
  self.fixture_table_names = []
  include AffiliateAdsHelper

  test 'enabled catalog entries contain approved compact copy and HTTPS creative URLs' do
    AffiliateAdsHelper::AFFILIATE_ADS.select { |ad| ad['enabled'] }.each do |ad|
      assert_equal true, ad['approved'], ad['id']
      assert ad.fetch('events').any?
      assert ad.fetch('placements').any?
      assert_operator ad.fetch('title').length, :<=, 36
      assert_operator ad.fetch('description').length, :<=, 70
      assert_operator ad.fetch('link_label').length, :<=, 24
      [ad.fetch('link_url'), ad['image_url'], ad['image_link_url'], *ad.fetch('tracking_pixels', [])].compact.each do |url|
        uri = URI.parse(url)
        assert_equal 'https', uri.scheme
        assert uri.host.present?
      end
      if ad['image_url']
        assert ad.fetch('image_alt').present?
        assert_operator ad.fetch('image_width'), :>, 0
        assert_operator ad.fetch('image_height'), :>, 0
      end
    end
  end

  test 'changing a program copy or disabling it changes the fragment cache key' do
    original = AffiliateAdsHelper::AFFILIATE_ADS.first
    refute_equal affiliate_ad_cache_key(original), affiliate_ad_cache_key(original.merge('title' => '別のコピー'))
    refute_equal affiliate_ad_cache_key(original), affiliate_ad_cache_key(original.merge('enabled' => false))
    assert_nil affiliate_ad_cache_key(nil)
  end
end
