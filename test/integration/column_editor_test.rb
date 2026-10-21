require 'test_helper'
require_relative '../support/chat_records'

class ColumnEditorTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  include ChatRecords

  setup do
    create_chat_records
    @master = Webmaster.create!(id: 1, email: 'article-editor@example.test', password: 'test-password-123')
  end

  test 'only the webmaster can write articles' do
    get new_column_path
    assert_redirected_to new_webmaster_session_path
    post admin_user_session_path, params: { admin_user: { email: @owner.email, password: 'test-password-123' } }
    assert_no_difference('Column.count') { post columns_path, params: article_params('publish') }
    assert_redirected_to new_webmaster_session_path
  end

  test 'editor offers templates products and separate draft and publish buttons' do
    login_master
    get new_column_path
    assert_response :success
    assert_select 'trix-editor[input="column-article-text"]'
    assert_select 'button[name="intent"][value="draft"]'
    assert_select 'button[name="intent"][value="publish"]'
    assert_select '[data-column-template]', count: 2
    assert_select 'input[name="column[column_products_attributes][0][amazon_url]"]'
    assert_select 'template[data-column-product-template]'
  end

  test 'drafts are private and can be previewed by the webmaster then explicitly published' do
    login_master
    post columns_path, params: { intent: 'draft', column: { title: '準備中の持ち物記事', text: '' } }
    article = Column.last
    assert_redirected_to edit_column_path(article)
    assert_not article.published?
    get column_path(article)
    assert_response :success
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_select '.column-preview-notice', text: /下書き/
    delete destroy_webmaster_session_path
    assert_raises(ActiveRecord::RecordNotFound) { get column_path(article) }
    get columns_path
    assert_select "a[href='#{column_path(article)}']", count: 0

    login_master
    patch column_path(article), params: article_params('publish')
    assert article.reload.published?
    assert_not_nil article.published_at
    delete destroy_webmaster_session_path
    get column_path(article)
    assert_response :success
    assert_select 'h1', text: '初参加の持ち物'
  end

  test 'invalid publication retains values and returns the new editor' do
    login_master
    post columns_path, params: { intent: 'publish', column: { title: '本文のない記事', text: '<div><br></div>' } }
    assert_response :unprocessable_entity
    assert_select 'input[name="column[title]"][value="本文のない記事"]'
    assert_select '[role="alert"]'
    assert_equal 0, Column.count
  end

  test 'product cards preserve tracking urls add disclosures and show click counts' do
    login_master
    post columns_path, params: article_params('publish').deep_merge(column: {
      affiliate: '0', column_products_attributes: { '0' => {
        name: '室内用シューズ', description: '足に合うサイズを選びます。',
        amazon_url: 'https://amzn.to/example', mercari_url: 'https://jp.mercari.com/search?keyword=shoes&afid=sample', position: 1
      } }
    })
    article = Column.last
    assert article&.published?, article&.errors&.full_messages&.join(', ')
    assert_equal 1, article.column_products.count
    get edit_column_path(article)
    assert_response :success
    assert_select '.column-product-fields .wm-meta', text: /Amazon 0 ／ メルカリ 0/
    delete destroy_webmaster_session_path
    get column_path(article)
    assert_response :success
    assert_select '.column-article__disclosure', text: /Amazonのアソシエイト/
    assert_select 'a[href="https://amzn.to/example"][rel="sponsored nofollow noopener"][data-column-shop="amazon"]'
    assert_select 'a[href="https://jp.mercari.com/search?keyword=shoes&afid=sample"][data-column-shop="mercari"]'
  end

  test 'blank product rows are ignored and a saved product can be removed' do
    login_master
    post columns_path, params: article_params('draft').deep_merge(column: { column_products_attributes: {
      '0' => { name: '', description: '', amazon_url: '', mercari_url: '', position: 0 }
    } })
    article = Column.last
    assert_redirected_to edit_column_path(article)
    assert_empty article.column_products
    product = article.column_products.create!(name: 'ビブス', amazon_url: 'https://www.amazon.co.jp/dp/example')
    patch column_path(article), params: { intent: 'draft', column: { column_products_attributes: { '0' => { id: product.id, _destroy: '1' } } } }
    assert_redirected_to edit_column_path(article)
    assert_not ColumnProduct.exists?(product.id)
  end

  test 'product links reject unsafe urls and another articles product cannot be edited' do
    login_master
    post columns_path, params: article_params('publish').deep_merge(column: { column_products_attributes: {
      '0' => { name: '道具', amazon_url: 'javascript:alert(1)' }
    } })
    assert_response :unprocessable_entity
    assert_equal 0, Column.count
    first = Column.create!(title: '記事1', text: '本文1')
    other = Column.create!(title: '記事2', text: '本文2')
    product = other.column_products.create!(name: '道具', amazon_url: 'https://amzn.to/example')
    assert_raises(ActiveRecord::RecordNotFound) do
      patch column_path(first), params: { intent: 'draft', column: { column_products_attributes: { '0' => { id: product.id, name: '不正な変更' } } } }
    end
    assert_equal '道具', product.reload.name
  end

  test 'article body removes unsafe markup and qualifies external affiliate links' do
    article = Column.create!(title: '選び方', publication_status: 'published', affiliate: true, text: '<div><h1>持ち物</h1><script>evil()</script><img src=x onerror=evil()><a href="javascript:evil()">不正</a><a href="https://amzn.to/example">新品</a><a href="/columns">一覧</a></div>')
    get column_path(article)
    assert_response :success
    assert_select 'h1', count: 1
    assert_select '.column-article__body h2', text: '持ち物'
    assert_select '.column-article__body script, .column-article__body img, a[href^="javascript:"]', count: 0
    assert_select '.column-article__body a[href="https://amzn.to/example"][rel="sponsored nofollow noopener"]'
    assert_select '.column-article__body a[href="/columns"]'
    login_master
    get edit_column_path(article)
    assert_response :success
    editor_value = css_select('#column-article-text').first['value']
    assert_includes editor_value, '<h1>持ち物</h1>'
    assert_not_includes editor_value, '<h2>'
  end

  test 'click tracking only counts public matching products and skips webmaster previews' do
    article = Column.create!(title: '備品', text: '必要な備品', publication_status: 'published')
    product = article.column_products.create!(name: 'ビブス', amazon_url: 'https://amzn.to/example')
    path = column_product_click_path(article, product)
    post path, params: { shop: 'amazon' }
    assert_response :no_content
    assert_equal 1, product.reload.amazon_clicks
    post path, params: { shop: 'mercari' }
    assert_response :unprocessable_entity
    post path, params: { shop: 'unknown' }
    assert_response :unprocessable_entity
    login_master
    post path, params: { shop: 'amazon' }
    assert_response :no_content
    assert_equal 1, product.reload.amazon_clicks
    article.update!(publication_status: 'draft')
    delete destroy_webmaster_session_path
    assert_raises(ActiveRecord::RecordNotFound) { post path, params: { shop: 'amazon' } }
  end

  test 'reader guides are limited to published matching audiences and sports' do
    participant = Column.create!(title: '参加者の持ち物', text: '持ち物', publication_status: 'published', audience: 'participant', event: @circle.event)
    organizer = Column.create!(title: '主催者の備品', text: '備品', publication_status: 'published', audience: 'organizer', event: @circle.event)
    Column.create!(title: '非公開', audience: 'all', publication_status: 'draft')
    guides = Column.for_readers(@circle.event_id, 'participant')
    assert_includes guides, participant
    assert_not_includes guides, organizer
    assert_equal ['参加者の持ち物'], guides.map(&:title)
    get columns_path, params: { audience: 'participant' }
    assert_select "a[href='#{column_path(participant)}']"
    assert_select "a[href='#{column_path(organizer)}']", count: 0
  end

  private

  def login_master
    post webmaster_session_path, params: { webmaster: { email: @master.email, password: 'test-password-123' } }
  end

  def article_params(intent)
    { intent: intent, column: { title: '初参加の持ち物', text: '<div>参加前に持ち物を確認しましょう。</div>', audience: 'participant', event_id: @circle.event_id } }
  end
end
