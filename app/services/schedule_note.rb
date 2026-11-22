class ScheduleNote
  TAGS = %w[p a br strong b em i del s ul ol li div h1 h2 h3 blockquote pre code].freeze

  def self.clean(html)
    return if html.nil?

    ActionController::Base.helpers.sanitize(html, tags: TAGS, attributes: %w[href])
  end
end
