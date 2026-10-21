module ColumnsHelper
  def column_meta_tags(column)
    metadata = ColumnSearchMetadata.for(column)
    canonical = column_url(column, host: 'circle-book.com', protocol: 'https')
    cover = column.image.identifier.present? ? column.image.url : URI.parse(default_ogp_image_url).request_uri
    cover = URI.join('https://circle-book.com', cover).to_s
    {
      title: metadata[:title], description: metadata[:description], canonical: canonical,
      og: { title: column.title, description: metadata[:description], type: 'article', url: canonical,
            site_name: 'サークルブック', locale: 'ja_JP', image: { _: cover, secure_url: cover, alt: column.title } },
      twitter: { card: 'summary_large_image', title: column.title, description: metadata[:description], image: cover, 'image:alt' => column.title },
      article: { published_time: (column.published_at&.iso8601 if column.published?), modified_time: column.updated_at&.iso8601 }
    }
  end

  def column_body_html(column)
    source = column.text.to_s
    source = simple_format(source) unless source.match?(/<(?:div|p|h[1-6]|ul|ol|table|blockquote)\b/i)
    safe = sanitize(Rinku.auto_link(source),
      tags: %w[p div br h1 h2 h3 h4 strong b em i del blockquote ul ol li a pre code table thead tbody tr th td],
      attributes: %w[href colspan rowspan])
    fragment = Nokogiri::HTML5.fragment(safe)
    fragment.css('h1').each { |heading| heading.name = 'h2' }
    fragment.css('a[href]').each do |link|
      href = link['href'].to_s
      if href.match?(/\Ahttps?:\/\//i)
        link['rel'] = column.affiliate? ? 'sponsored nofollow noopener' : 'noopener'
        link['target'] = '_blank'
      elsif !href.start_with?('/', '#') || href.start_with?('//')
        link.remove_attribute('href')
      end
    end
    fragment.to_html.html_safe
  end

  def column_editor_content(column)
    # Trix supports h1 as its heading block; rendering h2 back into the editor
    # would silently turn every saved heading into plain text on the next edit.
    fragment = Nokogiri::HTML5.fragment(column_body_html(column))
    fragment.css('h2, h3, h4').each { |heading| heading.name = 'h1' }
    fragment.to_html.html_safe
  end

  def column_article_content(column)
    products = column.column_products.to_a
    used = []
    fragment = Nokogiri::HTML5.fragment(column_body_html(column))
    fragment.css('p, div').each do |node|
      next if node.element_children.any? { |child| %w[p div h2 h3 h4 ul ol table blockquote pre].include?(child.name) }
      match = node.text.strip.match(/\A\[商品:([1-9]\d*)\]\z/)
      next unless match

      product = products[match[1].to_i - 1]
      if product && !used.include?(product)
        node.replace(render(partial: 'columns/product', locals: { product: product }))
        used << product
      else
        node.remove
      end
    end
    { html: fragment.to_html.html_safe, remaining_products: products - used }
  end

  def column_related_guides(event:, audience:)
    guides = Column.for_readers(event&.id, audience).includes(:event, :column_products)
    specific = event ? guides.where(event_id: event.id).limit(1).to_a : []
    specific.presence || guides.where(event_id: nil).limit(1).to_a
  end

  def column_product_link(product, shop)
    label = if shop == 'amazon'
      URI.parse(product.amazon_url).path == '/s' ? 'Amazonで候補を比較' : 'Amazonで商品を見る'
    else
      'メルカリで中古を探す'
    end
    link_to label, product.public_send("#{shop}_url"), class: "column-shop-link column-shop-link--#{shop}",
      target: '_blank', rel: 'sponsored nofollow noopener',
      data: (webmaster? ? {} : { column_shop: shop, column_click_url: column_product_click_path(product.column_id, product) })
  end
end
