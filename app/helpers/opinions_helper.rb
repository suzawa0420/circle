module OpinionsHelper
  def webmaster_opinion_body(body)
    # Opinions are plain text. Escape first; only our generated anchors become HTML.
    fragment = Nokogiri::HTML5.fragment(Rinku.auto_link(ERB::Util.html_escape(body.to_s), :urls))
    fragment.css('a').each do |link|
      # Rinku includes Japanese closing punctuation (and following prose) in URLs.
      if (ending = link.text.index(/[、。，．）］｝〉》」』】]/))
        trailing = link.text[ending..]
        link.content = link.text[0...ending]
        link['href'] = link['href'].split(/[、。，．）］｝〉》」』】]/, 2).first
        link.add_next_sibling(Nokogiri::XML::Text.new(trailing, fragment.document))
      end
      url = URI.parse(URI::DEFAULT_PARSER.escape(link['href'].to_s)) rescue nil
      unless url.is_a?(URI::HTTP) && url.host.present? && url.userinfo.nil?
        link.replace(link.children)
        next
      end
      link['class'] = 'message-url'
      link['target'] = '_blank'
      link['rel'] = 'noopener noreferrer nofollow'
    end
    safe_links = sanitize(fragment.to_html, tags: %w[a], attributes: %w[href class target rel])
    simple_format(safe_links, {}, sanitize: false)
  end
end
