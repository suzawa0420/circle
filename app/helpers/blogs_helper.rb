module BlogsHelper
  def blog_listing_structured_data(blogs)
    return unless public_structured_data_page?
    records = blogs.to_a
    ids = Blog.publicly_visible.where(id: records.map(&:id)).pluck(:id)
    entries = records.select { |blog| ids.include?(blog.id) }.map do |blog|
      { 'url' => "https://circle-book.com#{circle_blog_path(blog.user_id, blog.id)}", 'name' => blog.title.to_s }
    end
    structured_collection(entries, offset: blogs.respond_to?(:offset_value) ? blogs.offset_value : 0)
  end

  def blog_post_structured_data(blog)
    return unless public_structured_data_page? && blog.publicly_visible?
    url = "https://circle-book.com#{circle_blog_path(blog.user_id, blog)}"
    data = {
      '@context' => 'https://schema.org', '@type' => 'BlogPosting', '@id' => "#{url}#article", 'url' => url,
      'headline' => blog.title.to_s, 'articleBody' => structured_text(blog.content), 'inLanguage' => 'ja',
      'datePublished' => blog.created_at.iso8601, 'dateModified' => blog.updated_at.iso8601,
      'author' => { '@type' => 'Organization', '@id' => circle_schema_id(blog.user),
                    'name' => blog.user.name.to_s, 'url' => "https://circle-book.com#{circle_path(blog.user)}" },
      'mainEntityOfPage' => { '@type' => 'WebPage', '@id' => url }
    }
    images = [blog.image_01, blog.image_02, blog.image_03, blog.image_04].select { |image| image.identifier.present? }
      .filter_map { |image| structured_absolute_url(image.url) }
    data['image'] = images if images.any?
    data
  end
end
