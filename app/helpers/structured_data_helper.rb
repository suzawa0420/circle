module StructuredDataHelper
  def public_structured_data_page?
    request.get? && !webmaster? && !meta_tags[:noindex] &&
      !response.headers['X-Robots-Tag'].to_s.include?('noindex')
  end

  def structured_absolute_url(value)
    value = value.to_s.strip
    return if value.blank?
    uri = URI.join('https://circle-book.com/', value)
    uri.to_s if uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?
  rescue URI::InvalidURIError
    nil
  end

  def structured_page_url
    structured_absolute_url(breadcrumb_current_url)
  end

  def structured_text(value)
    strip_tags(value.to_s).squish
  end

  def structured_collection(entries, offset: 0, name: nil)
    return unless public_structured_data_page? && entries.any?
    url = structured_page_url
    {
      '@context' => 'https://schema.org', '@type' => 'ItemList', '@id' => "#{url}#list",
      'url' => url, 'name' => structured_text(name.presence || meta_tags[:title]), 'numberOfItems' => entries.length,
      'mainEntityOfPage' => {
        '@type' => 'CollectionPage', '@id' => url, 'url' => url,
        'isPartOf' => { '@type' => 'WebSite', '@id' => 'https://circle-book.com/#website',
                        'url' => 'https://circle-book.com/', 'name' => 'サークルブック' }
      },
      'itemListElement' => entries.each_with_index.map do |entry, index|
        { '@type' => 'ListItem', 'position' => offset.to_i + index + 1 }.merge(entry)
      end
    }
  end

  def circle_listing_structured_data(users)
    return unless public_structured_data_page?
    records = users.to_a
    public_ids = User.publicly_visible.where(id: records.map(&:id)).pluck(:id)
    entries = records.select { |user| public_ids.include?(user.id) }.map do |user|
      { 'url' => "https://circle-book.com#{circle_path(user)}", 'name' => user.name.to_s }
    end
    structured_collection(entries, offset: users.respond_to?(:offset_value) ? users.offset_value : 0)
  end

  def circle_schema_id(user)
    "https://circle-book.com#{circle_path(user)}#organization"
  end

  def circle_displayed_reviews(user)
    @circle_displayed_reviews ||= {}
    @circle_displayed_reviews[user.id] ||= user.reviews.includes(:member, :conversation_review)
      .order(created_at: :desc, id: :desc).limit(3).to_a
  end

  def circle_review_structured_data(review)
    author = review.member ? review.member.nickname : (review.nickname.presence || 'ゲストユーザー')
    return unless author.present? && review.comment.present? && [0, 1].include?(review.review)
    {
      '@type' => 'Review', '@id' => "https://circle-book.com#{user_reviews_path(review.user_id)}#review-#{review.id}",
      'author' => { '@type' => 'Person', 'name' => author.to_s }, 'reviewBody' => review.comment.to_s,
      'datePublished' => review.created_at.iso8601,
      'reviewRating' => { '@type' => 'Rating', 'ratingValue' => review.review, 'worstRating' => 0, 'bestRating' => 1 }
    }
  end

  def circle_profile_structured_data(user, reviews: circle_displayed_reviews(user))
    return unless public_structured_data_page? && user.publicly_visible?
    data = {
      '@context' => 'https://schema.org', '@type' => 'Organization', '@id' => circle_schema_id(user),
      'url' => "https://circle-book.com#{circle_path(user)}", 'name' => user.name.to_s,
      'description' => "#{user.prefecture.name}で活動している#{user.event.txt}",
      'areaServed' => { '@type' => 'AdministrativeArea', 'name' => user.prefecture.name.to_s },
      'mainEntityOfPage' => { '@type' => 'WebPage', '@id' => structured_page_url }
    }
    images = [user.pic_profile, user.gallery_01, user.gallery_02, user.gallery_03, user.gallery_04, user.pic_header]
      .select { |image| image.identifier.present? }.filter_map { |image| structured_absolute_url(image.url) }.uniq
    data['image'] = images if images.any?
    rating = review_aggregate_rating(user.review_score, review_count: user.reviews.count)
    data['aggregateRating'] = rating if rating
    visible_reviews = reviews.filter_map { |review| circle_review_structured_data(review) }
    data['review'] = visible_reviews if visible_reviews.any?
    data
  end

  def question_structured_data(question, user: question.user)
    return if structured_text(question.content).blank?
    url = "https://circle-book.com#{user_question_path(question.user_id, question)}"
    data = { '@type' => 'Question', '@id' => "#{url}#question", 'url' => url, 'name' => question.content.to_s }
    if structured_text(question.answer).present?
      data['acceptedAnswer'] = {
        '@type' => 'Answer', '@id' => "#{url}#answer", 'url' => "#{url}#answer", 'text' => question.answer.to_s,
        'author' => { '@type' => 'Organization', '@id' => circle_schema_id(user), 'name' => user.name }
      }
    end
    data
  end

  def answered_faq_structured_data(questions, user: nil)
    return unless public_structured_data_page?
    answered = questions.filter_map { |question| question_structured_data(question, user: user || question.user) }
      .select { |question| question.key?('acceptedAnswer') }
    return if answered.empty?
    { '@context' => 'https://schema.org', '@type' => 'FAQPage',
      '@id' => "#{structured_page_url}#faq", 'mainEntity' => answered }
  end

  def circle_faq_structured_data(user)
    return unless public_structured_data_page? && user.publicly_visible?
    return if user.review_permit == false || AccountBlock.exists?(ip_address: request.remote_ip)
    answered_faq_structured_data(@questions || user.questions.order(created_at: :desc), user: user)
  end

  def question_page_structured_data(question, user:)
    return unless public_structured_data_page? && user.publicly_visible?
    { '@context' => 'https://schema.org', '@type' => 'WebPage', '@id' => structured_page_url,
      'url' => structured_page_url, 'name' => question.content.to_s,
      'mainEntity' => question_structured_data(question, user: user) }
  end

  def questions_listing_structured_data(questions, user:)
    return unless public_structured_data_page? && user.publicly_visible?
    entries = questions.map do |question|
      { 'name' => question.content.to_s, 'url' => "https://circle-book.com#{user_question_path(user, question)}" }
    end
    structured_collection(entries, offset: questions.respond_to?(:offset_value) ? questions.offset_value : 0)
  end

  def reviews_listing_structured_data(reviews)
    return unless public_structured_data_page?
    records = reviews.to_a
    ids = User.publicly_visible.where(id: records.map(&:user_id)).pluck(:id)
    entries = records.filter_map do |review|
      next unless ids.include?(review.user_id)
      data = circle_review_structured_data(review)
      next unless data
      data['itemReviewed'] = { '@type' => 'Organization', '@id' => circle_schema_id(review.user), 'name' => review.user.name }
      { 'item' => data }
    end
    structured_collection(entries, offset: reviews.respond_to?(:offset_value) ? reviews.offset_value : 0)
  end

  # Both facility ratings and circle recommendation averages use a 0–5 scale.
  # Do not invent a zero rating for missing aggregates or clamp invalid values.
  def review_aggregate_rating(score, review_count:)
    rating = Float(score, exception: false)
    return unless review_count.positive? && rating&.finite? && rating.between?(0, 5)

    {
      '@type' => 'AggregateRating',
      'ratingValue' => rating,
      'worstRating' => 0,
      'bestRating' => 5,
      'reviewCount' => review_count
    }
  end
end
