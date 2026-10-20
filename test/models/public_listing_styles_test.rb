require 'test_helper'
require Rails.root.join('lib/public_listing_styles')

class PublicListingStylesTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test 'listing asset keeps PICTE ad styles from its nested shared partial' do
    css = Rails.application.assets.find_asset('public_listing.css').to_s
    %w[.picte-ad .picte-ad__label .picte-ad__image .picte-ad__title .picte-ad__cta .picte-ad-slot].each do |selector|
      assert_includes css, selector
    end
    assert_includes css, '1280/853'
  end

  test 'compiled listing asset preserves shared sorting controls and selected state' do
    css = Rails.application.assets.find_asset('public_listing.css').to_s
    assert_match(/\.cb-sort\{[^}]*display:\s*flex/, css)
    assert_match(/\.cb-sort__item\{[^}]*justify-content:\s*center/, css)
    assert_match(/\.cb-sort__item\.is-selected\{[^}]*background:/, css)
  end

  test 'compiled listing asset retains shared event date controls' do
    css = Rails.application.assets.find_asset('public_listing.css').to_s
    assert_match(/\.event-results__days\{[^}]*display:\s*flex/, css)
    assert_match(/\.event-results__days\{[^}]*overflow-x:\s*auto/, css)
    assert_match(/\.event-results__days\{[^}]*flex-wrap:\s*nowrap/, css)
    assert_includes css, '.event-date-search'
  end

  test 'detail asset preserves gallery FAQ warnings and mobile navigation without editor styles' do
    css = Rails.application.assets.find_asset('public_detail.css').to_s
    %w[.header_imege .popup .circle-faq__question .circle-contact-warning .mobile-circle-summary .readmore-content].each do |selector|
      assert_includes css, selector
    end
    refute_includes css, '.trix-button-group'
    assert_operator css.bytesize, :<, Rails.application.assets.find_asset('application.css').to_s.bytesize
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

  test 'directory asset keeps facility cards calendar states and shared navigation' do
    css = Rails.application.assets.find_asset('public_directory.css').to_s
    %w[.place-card .places-filter .schedule-calendar__grid .schedule-calendar__day.is-today
       .schedule-calendar__day.is-selected .status-cancelled .mobile-circle-summary].each do |selector|
      assert_includes css, selector
    end
    refute_includes css, '.trix-button-group'
    assert_match(/\.mobile-circle-summary\{[^}]*display:\s*block/, css)
    assert_match(/\.mobile-circle-summary__identity\{[^}]*display:\s*flex/, css)
    assert_operator css.bytesize, :<, Rails.application.assets.find_asset('application.css').to_s.bytesize / 2
  end
end
