module ChatMessagesHelper
  def chat_message_body(body)
    # Messages are plain text: escape user HTML before adding URL anchors.
    linked = Rinku.auto_link(ERB::Util.html_escape(body.to_s), :urls,
                             'class="message-url" target="_blank" rel="noopener noreferrer nofollow"')
    safe_links = sanitize(linked, tags: %w[a], attributes: %w[href class target rel])
    simple_format(safe_links, {}, sanitize: false)
  end
end
