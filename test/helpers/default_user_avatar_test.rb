require 'test_helper'
require 'digest'

class DefaultUserAvatarTest < ActionView::TestCase
  self.fixture_table_names = []
  include ApplicationHelper

  test 'only explicit male and female values use their unchanged original images' do
    [1, '1'].each { |gender| assert_equal '/images/avatars/default-male-v1.png', default_user_avatar_path(gender) }
    [2, '2'].each { |gender| assert_equal '/images/avatars/default-female-v1.png', default_user_avatar_path(gender) }
  end

  test 'other unknown empty and nil gender values share the versioned neutral squirrel' do
    [0, '0', nil, '', 'other', 'unknown', '未登録', false, 9].each do |gender|
      assert_equal 'other', default_user_avatar_variant(gender)
      assert_equal '/images/avatars/default-other-v2.png', default_user_avatar_path(gender)
      avatar = Nokogiri::HTML.fragment(default_user_avatar_tag(gender)).at_css('.default-user-avatar--other')
      assert_equal 'true', avatar['aria-hidden']
      assert_equal '/images/avatars/default-other-v2.png', avatar.at_css('img')['src']
    end
  end

  test 'uploaded pictures stay ahead of fallback and are not masked as default avatars' do
    picture = Struct.new(:url).new('/uploads/existing-person.png')
    person = Struct.new(:image_profile, :gender, :nickname).new(picture, nil, '画像ありの参加者')
    conversation = Struct.new(:person) { def person(_role) = self[:person] }.new(person)
    html = render partial: 'conversations/avatar', locals: { conversation: conversation, role: 'member' }
    avatar = Nokogiri::HTML.fragment(html)
    assert_equal '/uploads/existing-person.png', avatar.at_css('img')['src']
    assert_nil avatar.at_css('.default-user-avatar')
    refute_includes html, 'default-other'
  end

  test 'blank-gender chat avatar uses the new neutral fallback' do
    person = Struct.new(:image_profile, :gender, :nickname).new(nil, nil, '未指定の参加者')
    conversation = Struct.new(:person) { def person(_role) = self[:person] }.new(person)
    html = render partial: 'conversations/avatar', locals: { conversation: conversation, role: 'member' }
    assert Nokogiri::HTML.fragment(html).at_css('img[src="/images/avatars/default-other-v2.png"]')
  end

  test 'new delivery image and corresponding mask are valid and keep interior artwork' do
    png = File.binread(Rails.root.join('public/images/avatars/default-other-v2.png'))
    assert_equal "\x89PNG\r\n\x1a\n".b, png.byteslice(0, 8)
    assert_equal [256, 256], png.byteslice(16, 8).unpack('NN')
    mask = Nokogiri::XML(File.read(Rails.root.join('public/images/avatars/default-other-mask-v2.svg')))
    assert_empty mask.errors
    assert_equal '0 0 256 256', mask.root['viewBox']
    assert mask.at_css('path')['d'].length > 100
  end

  test 'public detail CSS keeps the new neutral mask while private CSS retains original male female masks' do
    detail = Rails.application.assets.find_asset('public_detail.css').to_s
    assert_includes detail, '.default-user-avatar--other'
    assert_includes detail, '/images/avatars/default-other-mask-v2.svg'
    stylesheet = Rails.application.assets.find_asset('application.css').to_s
    %w[male female].each do |variant|
      assert_includes stylesheet, "/images/avatars/default-#{variant}-mask-v1.svg"
    end
  end
end
