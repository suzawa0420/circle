module ChatMessagesHelper
  def automatic_message_body(body)
    lines = body.to_s.split("\n")
    return chat_message_body(body) unless lines.first == '直近の活動日は以下です。'
    pairs = lines.drop(1).each_slice(2).to_a
    return chat_message_body(body) unless pairs.length.between?(2, 4) && pairs.all? { |label, url| label.present? && url.to_s.match?(%r{\Ahttps://circle-book\.com/users/\d+/schedules(?:/\d+)?\z}) }

    schedule_links = pairs[0...-1].map do |label, url|
      content_tag(:li, link_to(label, url, class: 'inquiry-schedule-link'))
    end
    safe_join([
      content_tag(:p, lines.first),
      content_tag(:ul, safe_join(schedule_links), class: 'inquiry-schedule-list'),
      link_to('他のスケジュールを見る', pairs.last.last, class: 'cb-button cb-button--primary')
    ])
  end

  def chat_message_body(body)
    # Messages are plain text: escape user HTML before adding URL anchors.
    linked = Rinku.auto_link(ERB::Util.html_escape(body.to_s), :urls,
                             'class="message-url" target="_blank" rel="noopener noreferrer nofollow"')
    safe_links = sanitize(linked, tags: %w[a], attributes: %w[href class target rel])
    simple_format(safe_links, {}, sanitize: false)
  end
end
