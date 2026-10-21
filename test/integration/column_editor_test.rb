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
    assert_select '.column-article__disclosure p', text: '広告：この記事にはアフィリエイト広告が含まれます。'
    assert_select '.column-article__disclosure', text: /Amazonのアソシエイト/, count: 0
    assert_select '.column-article__amazon-disclosure', text: /Amazonのアソシエイト/
    assert_select '.column-article__disclosure a[href="/advertising"]'
    assert_select 'a[href="https://amzn.to/example"][rel="sponsored nofollow noopener"][data-column-shop="amazon"]'
    assert_select 'a[href="https://jp.mercari.com/search?keyword=shoes&afid=sample"][data-column-shop="mercari"]'
  end

  test 'large article covers are shown above the lead and used for social previews and directory cards' do
    login_master
    Tempfile.create(['column-cover', '.png']) do |file|
      MiniMagick::Tool::Convert.new do |image|
        image.size '1800x1200'
        image << 'xc:#e8f0e9'
        image << file.path
      end
      upload = Rack::Test::UploadedFile.new(file.path, 'image/png')
      post columns_path, params: article_params('publish').deep_merge(column: { image: upload })
      article = Column.last
      assert_redirected_to edit_column_path(article)
      stored = MiniMagick::Image.open(article.image.path)
      assert_equal 1600, stored.width
      assert_operator stored.height, :>, 400
      delete destroy_webmaster_session_path
      get column_path(article)
      assert_select '.column-article__header img.column-article__image[fetchpriority="high"]'
      assert_select 'meta[property="og:image"]' do |images|
        assert_includes images.first['content'], article.image.identifier
      end
      get columns_path
      assert_select '.column-directory__card img', count: 1
    ensure
      article&.image&.remove!
    end
  end

  test 'numeric dynamically added rows persist image cards and retain affiliate destinations' do
    login_master
    post columns_path, params: article_params('publish').deep_merge(column: { column_products_attributes: {
      '0' => { name: 'ボール', amazon_url: 'https://www.amazon.co.jp/dp/B07PWNBKFJ?tag=sample-22', image_url: 'https://m.media-amazon.com/images/I/ball.jpg' },
      '17925458327440' => { name: 'ビブス', amazon_url: 'https://www.amazon.co.jp/s?k=bibs&tag=sample-22', image_url: 'https://m.media-amazon.com/images/I/bibs.jpg', position: 1 }
    } })
    article = Column.last
    assert_equal 2, article.column_products.count
    delete destroy_webmaster_session_path
    get column_path(article)
    assert_response :success
    assert_select '.column-product__image-link img', count: 2
    assert_select '.column-product__image-link[rel="sponsored nofollow noopener"][data-column-shop="amazon"]', count: 2
    assert_select '.column-product__image-link[href="https://www.amazon.co.jp/s?k=bibs&tag=sample-22"]'
    assert_select '.column-product__image[referrerpolicy="no-referrer"]', count: 2
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

  test 'product cards appear between body paragraphs once with remaining products at the end' do
    article = Column.create!(title: '本文の商品紹介', text: '<h1>服を選ぶ</h1><p>シャツの説明</p><p><strong>[商品:2]</strong></p><p>着た状態で確認</p><div>[商品:2]</div><h1>靴を選ぶ</h1><div>[商品:1]</div>', publication_status: 'draft')
    shoes = article.column_products.create!(name: 'シューズ', amazon_url: 'https://amzn.to/shoes', position: 0)
    shirt = article.column_products.create!(name: 'シャツ', amazon_url: 'https://www.amazon.co.jp/s?k=shirt&tag=sample-22', image_url: 'https://m.media-amazon.com/images/I/shirt.jpg', position: 1)
    article.column_products.create!(name: 'タオル', amazon_url: 'https://amzn.to/towel', position: 2)
    article.update!(publication_status: 'published')
    get column_path(article)
    assert_response :success
    assert_select '.column-article__body .column-product', count: 2
    assert_select '.column-article__body .column-product h3', text: 'シャツ', count: 1
    assert_select '.column-products .column-product', count: 1
    assert_select '.column-products .column-product h3', text: 'タオル'
    assert_select '.column-article__body .column-product__image-link img', count: 1
    assert_select '.column-article__body a[data-column-click-url="' + column_product_click_path(article, shirt) + '"]', text: 'Amazonで候補を比較'
    assert_select '.column-article__body a[data-column-click-url="' + column_product_click_path(article, shoes) + '"]', text: 'Amazonで商品を見る'
    assert_not_includes css_select('.column-article__body').first.text, '[商品:'
    body = css_select('.column-article__body').first.inner_html
    assert_operator body.index('シャツの説明'), :<, body.index('shirt.jpg')
    assert_operator body.index('shirt.jpg'), :<, body.index('着た状態で確認')
    login_master
    get edit_column_path(article)
    assert_includes css_select('#column-article-text').first['value'], '[商品:2]'
    assert_select '[data-column-insert-product]', count: 4 # Includes the new-row template.
  end

  test 'missing product slots cannot be published and drafts do not show unresolved markers' do
    article = Column.create!(title: '商品準備中', text: '<p>[商品:12]</p>')
    assert_not article.update(publication_status: 'published')
    assert_includes article.errors[:text].join, '商品カード番号'
    login_master
    get column_path(article)
    assert_response :success
    assert_not_includes css_select('.column-article__body').first.text, '[商品:'
  end

  test 'advertising page is public linked from the footer and contains the Amazon statement' do
    get advertising_path
    assert_response :success
    assert_select 'h1', text: '広告・アフィリエイトについて'
    assert_select 'p', text: 'Amazonのアソシエイトとして、サークルブックは適格販売により収入を得ています。'
    assert_select 'h2', text: 'A8.netのアフィリエイト広告について'
    assert_select 'h2', text: 'Google AdSenseについて'
    assert_select 'a[href="/privacypolicy#advertising-cookies"]'
    assert_select '.footer_links a[href="/advertising"]'
    assert_select 'a[href="/privacypolicy"]'
    get privacypolicy_path
    assert_response :success
    assert_select '#advertising-cookies', text: '6. Cookie・広告・外部サービス'
    assert_select 'a[href="https://myadcenter.google.com/"]'
    assert_select 'a[href="https://optout.aboutads.info/"]'
  end

  test 'six editorial guides have distinct search metadata canonical social tags and unchanged headings' do
    ColumnSearchMetadata::PROFILES.each do |id, profile|
      article = Column.create!(id: id, title: profile.fetch('heading'), text: '<p>活動の準備と道具の選び方。</p>', publication_status: 'published')
      get column_path(article), params: { utm_source: 'share', preview: '1' }
      assert_response :success
      canonical = "https://circle-book.com/columns/#{id}"
      assert_select 'title', text: "#{profile.fetch('title')} | サークルブック"
      assert_select 'h1', text: profile.fetch('heading')
      assert_select 'meta[name="description"]', count: 1 do |tags|
        assert_equal profile.fetch('description'), tags.first['content']
      end
      assert_select 'link[rel="canonical"]', count: 1 do |links|
        assert_equal canonical, links.first['href']
      end
      { 'og:title' => article.title, 'og:description' => profile.fetch('description'), 'og:type' => 'article', 'og:url' => canonical,
        'og:image:alt' => article.title }.each do |property, value|
        assert_select "meta[property='#{property}']", count: 1 do |tags|
          assert_equal value, tags.first['content']
        end
      end
      assert_select 'meta[property="og:image"]', count: 1 do |tags|
        assert_match %r{\Ahttps://}, tags.first['content']
      end
      assert_select 'meta[name="twitter:card"][content="summary_large_image"]'
      assert_select 'meta[name="twitter:title"]' do |tags|
        assert_equal article.title, tags.first['content']
      end
      assert_select 'meta[name="twitter:description"]' do |tags|
        assert_equal profile.fetch('description'), tags.first['content']
      end
      assert_select 'meta[name="robots"][content*="noindex"]', count: 0
    end
  end

  test 'changed article headings and ordinary articles use their current metadata rather than a stale profile' do
    article = Column.create!(id: 1, title: '新しく書き直した準備ガイド', description: 'この内容に合う説明文。', text: '<p>本文</p>', publication_status: 'published')
    get column_path(article)
    assert_select 'title', text: '新しく書き直した準備ガイド | サークルブック'
    assert_select 'meta[name="description"][content="この内容に合う説明文。"]'
    article.update!(description: '', text: '<p>本文の要約を使用します。</p>')
    get column_path(article)
    assert_select 'meta[name="description"][content="本文の要約を使用します。"]'
    login_master
    get column_path(article)
    assert_select 'meta[name="robots"][content*="noindex"]'
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
