require 'test_helper'
require_relative '../support/chat_records'
require 'active_support/testing/constant_stubbing'

class A8ProgramAdsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords
  include ActiveSupport::Testing::ConstantStubbing

  setup do
    create_chat_records
    @events = %w[game cooking gathering study basketball camping camera english].to_h do |slug|
      [slug, Event.create!(name: "検証種目#{slug}", ruby: slug, category: @circle.category, order: '2')]
    end
  end

  test 'venue programs follow the organizers own selected circle genre' do
    login_owner
    { 'game' => 'spacemarket', 'cooking' => 'spacemarket', 'gathering' => 'instabase', 'study' => 'instabase' }.each do |genre, program|
      @circle.update!(event: @events.fetch(genre))
      get "/users/#{@circle.id}/mypage"
      assert_response :success
      assert_program(program, 'organizer_mypage')
      assert_select '.affiliate-ad__link', text: '外部サイトで会場を探す'
      assert_select '.affiliate-ad__description', text: /外部サイト/
    end
    %w[basketball camping camera english].each do |genre|
      @circle.update!(event: @events.fetch(genre))
      get "/users/#{@circle.id}/mypage"
      assert_select '.affiliate-ad', count: 0
    end
  end

  test 'venue programs never enter anonymous search event blog or participant placements' do
    %w[game cooking gathering study].each do |genre|
      @circle.update!(event: @events.fetch(genre))
      [event_path(genre), "/dates/#{genre}", blogs_event_path(genre), circle_blogs_path(@circle)].each do |path|
        get path
        assert_response :success
        assert_select '.affiliate-ad', count: 0
      end
    end
    post member_session_path, params: { member: { email: @member.email, password: 'test-password-123' } }
    @member.events << @events.fetch('game')
    @member.events << @events.fetch('gathering')
    get member_path(@member)
    assert_select '.affiliate-ad', count: 0
    get "/users/#{@circle.id}/mypage"
    assert_select '.affiliate-ad', count: 0
  end

  test 'alpen uses only the verified banner050 on participant pages and follows changing interests' do
    post member_session_path, params: { member: { email: @member.email, password: 'test-password-123' } }
    @member.events << @events.fetch('basketball')
    get member_path(@member)
    assert_program('alpen', 'participant_mypage')
    assert_select '.affiliate-ad__action', count: 0
    assert_select '.affiliate-ad__pixel', count: 1
    refute_includes response.body, 'サイズ交換1回無料'
    refute_includes response.body, '4BEQI4+E9T65M+3OSK+5ZMCI'
    get conversations_path
    assert_select '.affiliate-ad', count: 0
    get member_profile_path(@member)
    assert_select '.affiliate-ad', count: 0
    @member.events.clear
    get member_path(@member)
    assert_select '.affiliate-ad', count: 0
  end

  test 'alpen keeps the single existing insertion point and does not infer a genre from keywords' do
    @circle.update!(event: @events.fetch('basketball'))
    2.times do |i|
      copy = @circle.dup
      copy.assign_attributes(name: "用具検証サークル#{i}", unique_id: nil)
      copy.save!
    end
    get event_path('basketball')
    assert_program('alpen', 'search')
    assert_select '.circle-results-grid > li:nth-child(3).affiliate-ad-slot', count: 1
    assert_select '.circle-results-grid > .list_ad', count: 0
    get circles_search_index_path, params: { detailed: '1', event_id: @events.fetch('basketball').id, q: '該当なし' }
    assert_program('alpen', 'search_empty')
    get circles_search_index_path, params: { detailed: '1', q: 'バスケ用具' }
    assert_select '.affiliate-ad', count: 0
    get circles_path
    assert_select '.affiliate-ad', count: 0
  end

  test 'alpen follows the selected sport in events and blogs without changing recruitment links' do
    @circle.update!(event: @events.fetch('camping'))
    @circle.schedules.create!(day: Date.current.iso8601, title: 'キャンプの活動', venue: '検証用の公園')
    get '/dates/camping'
    assert_program('alpen', 'event_search')
    assert_select '.event-results__card', count: 1
    get blogs_event_path('camping')
    assert_program('alpen', 'blog_search_empty')
    blog = @circle.blogs.create!(title: 'キャンプの活動報告', content: '地域で楽しく活動しています。' * 20)
    get circle_blog_path(@circle, blog)
    assert_program('alpen', 'circle_blog')
    get circle_path(@circle)
    assert_select '.affiliate-ad', count: 0
  end

  test 'disabled or unapproved programs remain hidden and catalog order preserves one ad' do
    login_owner
    @circle.update!(event: @events.fetch('game'))
    %w[enabled approved].each do |attribute|
      catalog = AffiliateAdsHelper::AFFILIATE_ADS.map { |ad| ad.merge(attribute => false) }
      stub_const(AffiliateAdsHelper, :AFFILIATE_ADS, catalog) do
        @member.events << @events.fetch('basketball') unless @member.events.exists?(@events.fetch('basketball').id)
        assert_nil view_helper.affiliate_ad_for_member(@member)
        assert_nil view_helper.affiliate_ad_for_event(@events.fetch('basketball'), placement: 'search')
        get "/users/#{@circle.id}/mypage"
        assert_select '.affiliate-ad', count: 0
      end
    end
    @member.events << @events.fetch('english')
    assert_equal 'lancul', view_helper.affiliate_ad_for_member(@member).fetch('id')
  end

  test 'official banner text link and pixel URLs match the unchanged selected source materials' do
    %w[spacemarket instabase alpen].each do |id|
      ad = AffiliateAdsHelper::AFFILIATE_ADS.find { |candidate| candidate.fetch('id') == id }
      assert_equal '004', ad.fetch('site_id')
      banner = source_material(id, 'banner')
      creative = banner.at_css('a img')
      assert_equal banner.at_css('a')['href'], ad.fetch('image_link_url')
      assert_equal creative['src'], ad.fetch('image_url')
      assert_equal [creative['width'].to_i, creative['height'].to_i], [ad.fetch('image_width'), ad.fetch('image_height')]
      pixels = banner.css('img[width="1"]').map { |image| image['src'] }
      unless ad['banner_only']
        text = source_material(id, 'text')
        assert_equal text.at_css('a')['href'], ad.fetch('link_url')
        pixels += text.css('img[width="1"]').map { |image| image['src'] }
      end
      assert_equal pixels, ad.fetch('tracking_pixels')
    end
    alpen = AffiliateAdsHelper::AFFILIATE_ADS.find { |ad| ad['id'] == 'alpen' }
    assert_equal '050', alpen.fetch('banner_material_id')
    assert_nil alpen['text_material_id']
    assert_nil alpen['link_url']
  end

  test 'verified replacement creatives are enabled and rejected URLs are absent' do
    %w[alpen instabase].each do |id|
      ad = AffiliateAdsHelper::AFFILIATE_ADS.find { |candidate| candidate['id'] == id }
      assert_equal true, ad.fetch('enabled')
    end
    source = File.read(Rails.root.join('config/affiliate_ads.yml'))
    %w[s00000017210001017000 s00000026212001003000 4BEQI4+E9T65M+3OSK+5ZMCI].each do |rejected|
      refute_includes source, rejected
    end
    alpen = AffiliateAdsHelper::AFFILIATE_ADS.find { |ad| ad['id'] == 'alpen' }
    assert_includes alpen.fetch('description'), '地域や商品、注文条件'
  end

  private

  def source_material(id, type)
    Nokogiri::HTML.fragment(File.read(Rails.root.join('test/fixtures/files/affiliate_ads', "#{id}-#{type}.html")))
  end

  def view_helper
    @view_helper ||= Object.new.extend(AffiliateAdsHelper)
  end

  def login_owner
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
  end

  def assert_program(id, placement)
    ad = AffiliateAdsHelper::AFFILIATE_ADS.find { |candidate| candidate['id'] == id }
    assert_select '.affiliate-ad', count: 1
    assert_select ".affiliate-ad[data-affiliate-program='#{id}'][data-affiliate-placement='#{placement}']", count: 1
    assert_select '.affiliate-ad__pr', text: '広告'
    assert_select '.affiliate-ad__banner-link[href=?]', ad.fetch('image_link_url'), count: 1
    assert_select '.affiliate-ad__banner[src=?][width="300"][height="250"]', ad.fetch('image_url'), count: 1
    ad.fetch('tracking_pixels').each do |url|
      assert_select '.affiliate-ad__pixel[src=?][width="1"][height="1"]', url, count: 1
    end
    assert_select '.affiliate-ad a', minimum: 1 do |links|
      links.each do |link|
        assert_equal '_blank', link['target']
        %w[sponsored nofollow noopener].each { |value| assert_includes link['rel'].split, value }
      end
    end
  end
end
