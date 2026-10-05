require 'test_helper'

class LucideHelperTest < ActionView::TestCase
  self.fixture_table_names = []
  include LucideHelper

  test 'renders accessible decorative SVG with inheritable color and size' do
    icon = Nokogiri::HTML.fragment(lucide_icon('calendar-days', class: 'custom-icon')).at_css('svg')
    assert_equal 'currentColor', icon['stroke']
    assert_equal '1em', icon['width']
    assert_equal 'true', icon['aria-hidden']
    assert_equal 'false', icon['focusable']
    assert_includes icon['class'], 'cb-icon--calendar-days'
    assert_includes icon['class'], 'custom-icon'
    assert icon.at_css('path')
  end

  test 'escapes attributes and rejects unknown icon names' do
    output = lucide_icon('search', title: '<script>alert(1)</script>')
    refute_includes output, '<script>'
    assert_raises(KeyError) { lucide_icon('../untrusted') }
  end

  test 'public listing asset retains generated SVG classes without icon fonts' do
    css = Rails.application.assets.find_asset('public_listing.css').to_s
    assert_includes css, '.cb-icon--star'
    assert_includes css, '.cb-icon'
    refute_match(/Font Awesome|FontAwesome|fa-solid-900|fa-brands-400/, css)
  end
end
