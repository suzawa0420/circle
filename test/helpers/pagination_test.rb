require 'test_helper'

class PaginationTest < ActionView::TestCase
  self.fixture_table_names = []
  include Kaminari::Helpers::HelperMethods

  test 'first middle and last pages have compact controls with accessible current state' do
    [1, 2, 50, 100].each do |number|
      fragment = pagination(number)
      assert_operator fragment.css('.page-item').size, :<=, 7
      assert_operator fragment.css('.page-item:not(.disabled) .page-link').count { |n| n.text.match?(/\A\d+\z/) }, :<=, 3
      assert_equal number.to_s, fragment.at_css('[aria-current=page]').text
      assert_equal 0, fragment.css('.disabled a, .active a').size
      assert_equal(number > 1 ? 1 : 0, fragment.css('a[aria-label="前のページ"]').size)
      assert_equal(number < 100 ? 1 : 0, fragment.css('a[aria-label="次のページ"]').size)
      assert_equal 'ページ切り替え', fragment.at_css('nav')['aria-label']
    end
  end

  test 'page links retain filters and custom page parameters' do
    fragment = pagination(50, param_name: :review_page)
    fragment.css('a').each do |link|
      query = Rack::Utils.parse_nested_query(URI.parse(link['href']).query)
      assert_equal 'バスケ', query['q']
      assert query['review_page'].present?
      assert_nil query['page']
    end
  end

  test 'single page does not render a navigation' do
    collection = Kaminari.paginate_array([1]).page(1).per(10)
    assert_empty paginate(collection, params: { controller: '/circles/circles', action: 'index' })
  end

  private

  def pagination(number, **options)
    collection = Kaminari.paginate_array([], total_count: 1000).page(number).per(10)
    html = paginate(collection, **options, params: { controller: '/circles/circles', action: 'index', q: 'バスケ' })
    Nokogiri::HTML.fragment(html)
  end
end
