require 'test_helper'
require Rails.root.join('lib/public_listing_styles')

class PublicListingStylesTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test 'compiled listing asset preserves shared sorting controls and selected state' do
    css = Rails.application.assets.find_asset('public_listing.css').to_s
    assert_match(/\.cb-sort\{[^}]*display:\s*flex/, css)
    assert_match(/\.cb-sort__item\{[^}]*justify-content:\s*center/, css)
    assert_match(/\.cb-sort__item\.is-selected\{[^}]*background:/, css)
  end

  test 'retains responsive rules aliases pseudo states and important declarations' do
    input = '@font-face{font-family:icon;src:url(icon.woff2)}' \
      '@media(min-width:768px){.used:hover,.unused{color:red!important}.editor{padding:1px}}' \
      '.used:not(.open){margin:0}html{box-sizing:border-box}.editor{color:blue}'
    output = PublicListingStyles.filter(input, Set['used', 'open'])
    assert_includes output, '@font-face'
    assert_includes output, '@media (min-width:768px)'
    assert_includes output, 'color:red!important'
    assert_includes output, '.used:not(.open)'
    assert_includes output, 'html{box-sizing:border-box;}'
    refute_includes output, '.editor'
  end
end
