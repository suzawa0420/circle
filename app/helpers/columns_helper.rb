module ColumnsHelper
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

  def column_related_guides(event:, audience:)
    Column.for_readers(event&.id, audience).limit(3).to_a
  end

  def column_product_link(product, shop)
    label = shop == 'amazon' ? 'Amazonで新品を確認' : 'メルカリで中古を探す'
    link_to label, product.public_send("#{shop}_url"), class: "column-shop-link column-shop-link--#{shop}",
      target: '_blank', rel: 'sponsored nofollow noopener',
      data: (webmaster? ? {} : { column_shop: shop, column_click_url: column_product_click_path(product.column_id, product) })
  end
end
