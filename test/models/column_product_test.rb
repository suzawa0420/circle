require 'test_helper'

class ColumnProductTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test 'new articles default to private drafts' do
    article = Column.create!(title: '執筆中の記事')
    assert_not article.published?
    assert_nil article.published_at
    assert_not_includes Column.published, article
  end

  test 'shop urls must be https on an allowed exact hostname without credentials' do
    article = Column.create!(title: '道具の選び方')
    product = article.column_products.build(name: 'ビブス')
    ['https://amazon.co.jp.evil.test/item', 'https://user:password@amazon.co.jp/item', 'http://amazon.co.jp/item', '//amazon.co.jp/item', 'https://amazon.co.jp:8443/item', 'javascript:alert(1)'].each do |url|
      product.amazon_url = url
      assert_not product.valid?, url
    end
    product.amazon_url = ' https://amzn.to/example?tag=example-22 '
    assert product.valid?
    assert_equal 'https://amzn.to/example?tag=example-22', product.amazon_url
    product.amazon_url = nil
    product.mercari_url = 'https://jp.mercari.com/search?keyword=ball&afid=sample'
    assert product.valid?
  end
end
