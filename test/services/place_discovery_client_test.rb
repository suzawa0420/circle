require 'test_helper'
require 'minitest/mock'

class PlaceDiscoveryClientTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test 'client refuses offhost redirects private IPs and query URLs before HTTP' do
    client = PlaceImports::DiscoveryClient.new(root: 'https://www.pref.example.jp/')
    %w[http://www.pref.example.jp/ https://elsewhere.jp/ https://www.pref.example.jp/?x=1 https://user@www.pref.example.jp/ https://www.pref.example.jp/#x].each do |url|
      assert_raises(PlaceImports::OfficialClient::FetchError) { client.get(url) }
    end
    %w[127.0.0.1 10.0.0.1 169.254.169.254 ::1 fc00::1 ::ffff:127.0.0.1].each do |address|
      Resolv.stub(:getaddresses, [address]) do
        error = assert_raises(PlaceImports::OfficialClient::FetchError) { client.get('https://www.pref.example.jp/') }
        assert_equal 'unapproved_url', error.message
      end
    end
  end
end
